#!/usr/bin/env bash
# setup-evals.sh - host hook for the `nebula-evals` config
# (.drupalaibp/nebula-evals.json). Ported from freelygive/canvas-storybook-ai's
# .drupalaibp/setup-evals.sh; the two kits share the eval set (custom/) so
# they grade the same cases, and this script stays in step with that one
# except for the final arming step (a Nebula bed has no local Drupal and is
# armed by the instrument's `abp-eval nebula`, see NEBULA-ARM.md).
#
# Resolves the eval instrument (core/), overlays this project's own eval set
# (custom/) onto fetched instruments, and builds the referee image when
# docker is available. The instrument's canonical home is the
# drupal/ai_best_practices repository; this project only pins a revision of
# it - never a drifting copy.
#
# Resolution order for core/:
#   1. $ABP_CORE_DIR             - development: use a local checkout in place
#                                  (composer path-repo style). Nothing fetched,
#                                  nothing overlaid; the checkout is authority,
#                                  including its own dataset - the committed
#                                  custom/ set is NOT consumed in this mode.
#   2. existing fetched core/    - a directory this script fetched earlier
#                                  (carries .abp-fetched): revision verified
#                                  against core.pin, refetched on mismatch.
#                                  A manually placed checkout WITHOUT the
#                                  marker is refused, never overlaid.
#   3. core.pin                  - clone the pinned repo@rev into core/
#                                  (temp dir + verify + atomic rename).
#
# Every scoreboard records which instrument revision graded it (abp_git_sha
# + dirty flag in the run manifest). Overlaid sets make a fetched core
# report dirty=true by design - the overlay IS a modification of the
# instrument checkout, and the boards say so until the instrument grows a
# native set-directory seam.
set -euo pipefail

# The installer stages hook scripts to the PROJECT ROOT and runs them there
# (`bash ./setup-evals.sh`, cwd = project) - script location says nothing
# about where the eval tree lives. Resolve from the working directory, and
# fall back to the script's parent for a manual run from inside .drupalaibp/.
if [ -d "$PWD/.drupalaibp/evals" ]; then
  PROJECT="$PWD"
else
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT="$(cd "$_script_dir/.." && pwd)"
  [ -d "$PROJECT/.drupalaibp/evals" ] \
    || { echo "  [evals] FAIL: cannot locate .drupalaibp/evals from $PWD or $_script_dir" >&2; exit 1; }
fi
EVALS="$PROJECT/.drupalaibp/evals"
CORE="$EVALS/core"
PIN_FILE="$EVALS/core.pin"
MARKER=".abp-fetched"
LOG="$EVALS/setup-evals.log"

note() { printf '  [evals] %s\n' "$*"; }
ok_probe=false
ok_image=false

TMP_FETCH=""
trap 'rm -rf "${TMP_FETCH:-}"' EXIT

fetch_pin() {
  local url rev got
  url="$(sed -n 1p "$PIN_FILE")"; rev="$(sed -n 2p "$PIN_FILE")"
  [ -n "$url" ] && [ -n "$rev" ] || { note "core.pin is malformed (need URL line 1, rev line 2)"; exit 1; }
  # The pin is a FULL 40-hex commit sha: immutable, exact-comparable. Tags
  # and branches move; abbreviations would refetch forever on reuse checks.
  printf '%s' "$rev" | grep -qE '^[0-9a-f]{40}$' \
    || { note "core.pin rev must be a full 40-char commit sha, got: $rev"; exit 1; }
  note "fetching instrument $url @ $rev"
  TMP_FETCH="$(mktemp -d "$EVALS/.core-fetch.XXXXXX")"
  git clone --filter=blob:none "$url" "$TMP_FETCH/core"
  git -C "$TMP_FETCH/core" checkout --detach "$rev"
  got="$(git -C "$TMP_FETCH/core" rev-parse HEAD)"
  [ "$got" = "$rev" ] || { note "FAIL: checked-out rev $got does not match pin $rev"; exit 1; }
  : > "$TMP_FETCH/core/$MARKER"
  # No delete-first gap: the old core moves aside, the new one moves in,
  # and only then does the old one go away.
  if [ -d "$CORE" ]; then
    mv "$CORE" "$TMP_FETCH/core-old"
  fi
  mv "$TMP_FETCH/core" "$CORE"
  # Run boards are operator data living inside the fetched tree; deleting
  # them with the old core silently erased every board on each pin bump
  # (operator-reported: the web viewer's run list came up empty). Carry
  # them into the new core before the trap removes core-old.
  if [ -d "$TMP_FETCH/core-old/evals/canvas-migration/runs" ]; then
    mkdir -p "$CORE/evals/canvas-migration/runs"
    moved=0
    for d in "$TMP_FETCH/core-old/evals/canvas-migration/runs"/*; do
      [ -e "$d" ] || continue
      mv "$d" "$CORE/evals/canvas-migration/runs/" && moved=$((moved+1))
    done
    if [ "$moved" -gt 0 ]; then
      note "preserved $moved existing run board(s) across the refetch"
    fi
  fi
}

# --- 1. resolve the instrument ------------------------------------------------
overlay=true
if [ -n "${ABP_CORE_DIR:-}" ]; then
  CORE="$(cd "$ABP_CORE_DIR" && pwd)"
  overlay=false
  note "development mode: instrument = $CORE (ABP_CORE_DIR, not the pin)"
  note "note: development mode grades the checkout's own set, not custom/"
elif [ -d "$CORE" ] && [ ! -f "$CORE/$MARKER" ]; then
  note "FAIL: core/ exists but was not fetched by this script - refusing to touch it"
  note "  use ABP_CORE_DIR=$CORE for a dev checkout, or remove core/ to refetch the pin"
  exit 1
elif [ -f "$PIN_FILE" ]; then
  want="$(sed -n 2p "$PIN_FILE")"
  if [ -d "$CORE/.git" ] \
     && [ "$(git -C "$CORE" rev-parse HEAD 2>/dev/null)" = "$want" ]; then
    note "instrument already at the pinned rev ${want:0:12}, keeping it"
  else
    [ -d "$CORE" ] && note "existing fetch does not match the pin - refetching"
    fetch_pin
  fi
else
  note "no instrument: set ABP_CORE_DIR to an ai_best_practices checkout"
  note "(development phase - core.pin is written when the instrument MR lands)"
  exit 1
fi

SET_DIR="$CORE/evals/canvas-migration"
[ -f "$SET_DIR/run.py" ] || { note "FAIL: $SET_DIR/run.py missing - not an instrument checkout"; exit 1; }

# --- 2. overlay this project's set (fetched instruments only) ------------------
if [ "$overlay" = true ]; then
  note "overlaying custom/canvas-migration onto the instrument's sample set"
  cp -f "$EVALS/custom/canvas-migration/dataset.yaml" "$SET_DIR/dataset.yaml"
  cp -f "$EVALS"/custom/canvas-migration/harness/* "$SET_DIR/harness/"
  cp -f "$EVALS"/custom/canvas-migration/checks/* "$SET_DIR/checks/"
fi

# --- 3. geom-probe deps + referee image ----------------------------------------
if [ -d "$SET_DIR/geom-probe" ]; then
  if [ -d "$SET_DIR/geom-probe/node_modules" ]; then
    ok_probe=true
  elif npm ci --omit=dev --prefix "$SET_DIR/geom-probe" >"$LOG" 2>&1; then
    ok_probe=true
  else
    note "npm ci FAILED (log: $LOG)"
    note "  retry: npm ci --omit=dev --prefix $SET_DIR/geom-probe"
  fi
else
  note "instrument has no vendored geom-probe (pre-vendoring revision)"
fi
if command -v docker >/dev/null 2>&1; then
  # The Dockerfile's FROM takes the digest-pinned base as a build arg; the
  # pin ships with the instrument (harness/referee/base-image.pin). An
  # instrument without the pin predates it - skip rather than build an
  # unpinned image the launcher would refuse anyway.
  BASE_PIN_FILE="$SET_DIR/harness/referee/base-image.pin"
  if [ -f "$BASE_PIN_FILE" ]; then
    if docker build -q -t abp-referee:dev \
         --build-arg "BASE_IMAGE=$(head -1 "$BASE_PIN_FILE" | tr -d '[:space:]')" \
         -f "$SET_DIR/harness/referee/Dockerfile" "$SET_DIR" >>"$LOG" 2>&1; then
      ok_image=true
      # The :dev tag is global and mutable - every project's build overwrites
      # it, and a compose file that still says :dev silently keeps (or
      # adopts) the wrong image across rebuilds and restarts. Tag this build
      # with the instrument revision and point the generated compose at THAT:
      # when the rev changes the compose changes, cmp misses, and the service
      # is restarted onto the image just built. :dev stays for the host
      # referee launcher.
      _rev="$(git -C "$CORE" rev-parse --short=12 HEAD 2>/dev/null || true)"
      _dirty=""
      [ -n "$(git -C "$CORE" status --porcelain 2>/dev/null | head -1)" ] && _dirty="-dirty"
      IMG_TAG="abp-referee:${_rev:-dev}${_dirty}"
      docker tag abp-referee:dev "$IMG_TAG" >>"$LOG" 2>&1 || IMG_TAG="abp-referee:dev"
    else
      note "referee image build FAILED (log: $LOG)"
      note "  retry: docker build -t abp-referee:dev --build-arg BASE_IMAGE=\$(cat $BASE_PIN_FILE) -f $SET_DIR/harness/referee/Dockerfile $SET_DIR"
    fi
  else
    note "instrument ships no referee base-image.pin (pre-pin revision) - referee image skipped"
  fi
else
  note "docker CLI not found - referee image skipped"
fi

# --- 3b. referee as a ddev service + web-container mask -------------------------
# Two jobs, one generated compose file (machine-specific - uid, socket gid,
# absolute paths - so it is gitignored and regenerated by re-running this
# script):
#   1. web.tmpfs masks .drupalaibp/evals from the SUT: the graded agent
#      works inside the web container and must not read the datasets,
#      rubrics or calibrated fixtures (bed git history is handled by
#      finalize-evals.sh). The host keeps the real tree through the same
#      bind mount - the mask is per-service.
#   2. abp-eval promotes the referee image to a ddev service so `ddev eval`
#      runs entirely in-container (host needs only docker + ddev). Mount
#      and hardening flags mirror harness/referee/referee-grade.sh: project
#      read-only at its host path, .abp-eval/ and runs/ writable, socket
#      read-only, caps dropped, unprivileged host uid. Hostnames resolve to
#      the router via external_links - no IPs baked in.
ok_compose=false
COMPOSE_FILE="$PROJECT/.ddev/docker-compose.abp-eval.yaml"
if $ok_image; then
  NAME="$(sed -n "s/^name:[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9._-]*\).*/\1/p" \
            "$PROJECT/.ddev/config.yaml" 2>/dev/null | head -1)"
  docker_endpoint="${DOCKER_HOST:-}"
  if [ -z "$docker_endpoint" ]; then
    docker_endpoint="$(docker context inspect "$(docker context show)" \
                         --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  fi
  docker_socket=""
  case "$docker_endpoint" in unix://*) docker_socket="${docker_endpoint#unix://}" ;; esac
  if [ -z "$NAME" ]; then
    note "cannot read the project name from .ddev/config.yaml - eval service skipped"
  elif [ -z "$docker_socket" ] || [ ! -S "$docker_socket" ]; then
    note "no local unix docker socket ($docker_endpoint) - eval service skipped"
  else
    socket_gid="$(stat -c %g "$docker_socket" 2>/dev/null || stat -f %g "$docker_socket")"
    # The gid that grants access is the one the socket carries INSIDE a
    # container, not on the host: Docker Desktop (macOS) forwards its VM's
    # socket into containers as root:root whatever the host file says, so
    # the host-side gid grants nothing there (operator-reported: every
    # docker call from the service denied on mac). Probe through the
    # referee image - on Linux the bind mount preserves ownership and this
    # returns the same gid stat already saw.
    container_gid="$(docker run --rm \
        -v "$docker_socket:/var/run/docker.sock" \
        abp-referee:dev stat -c %g /var/run/docker.sock 2>/dev/null || true)"
    socket_groups="      - \"$socket_gid\""$'\n'
    probe_groups=(--group-add "$socket_gid")
    if [ -n "$container_gid" ] && [ "$container_gid" != "$socket_gid" ]; then
      socket_groups="$socket_groups      - \"$container_gid\""$'\n'
      probe_groups+=(--group-add "$container_gid")
    fi
    # Functional preflight, not an ownership guess: can the service's user
    # actually reach the daemon with those groups? If not (Docker Desktop
    # exposing the socket 0600), fall back to container-root - on Docker
    # Desktop that is still unprivileged relative to the host, and
    # bind-mount writes land as the operator's own user via file sharing.
    svc_user="$(id -u):$(id -g)"
    if ! docker run --rm --user "$svc_user" "${probe_groups[@]}" \
           -v "$docker_socket:/var/run/docker.sock" \
           abp-referee:dev docker version >/dev/null 2>&1; then
      if docker run --rm --user 0:0 \
           -v "$docker_socket:/var/run/docker.sock" \
           abp-referee:dev docker version >/dev/null 2>&1; then
        svc_user="0:0"
        note "docker socket needs container-root (Docker Desktop) - eval service runs as root in-container"
      else
        note "WARNING: docker socket unreachable from a container as any user - ddev eval will fail"
        note "  on Docker Desktop, enable: Settings > Advanced > 'Allow the default Docker socket to be used'"
      fi
    fi
    TZ_NAME="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    mkdir -p "$SET_DIR/runs" "$PROJECT/.abp-eval"
    # Development mode: the instrument checkout lives outside the project
    # bind mount, so it needs its own read-only mount (runs/ rw on top).
    extra_mount=""
    case "$CORE/" in
      "$PROJECT"/*) ;;
      *) extra_mount="      - $CORE:$CORE:ro"$'\n' ;;
    esac
    TMP_COMPOSE="$(mktemp)"
    cat > "$TMP_COMPOSE" <<EOF
# GENERATED by .drupalaibp/setup-evals.sh - machine-specific, gitignored.
# Regenerate with: bash .drupalaibp/setup-evals.sh   (see the script header
# for what each block does and why).
services:
  web:
    tmpfs:
      - /var/www/html/.drupalaibp/evals
  abp-eval:
    image: ${IMG_TAG:-abp-referee:dev}
    container_name: ddev-${NAME}-abp-eval
    labels:
      com.ddev.site-name: ${NAME}
      com.ddev.approot: ${PROJECT}
      # Required for the router: ddev builds the published-port list only
      # from containers carrying this label, so without it *_EXPOSE above
      # is routed by traefik but never reaches the host ("No valid EntryPoint").
      com.ddev.platform: ddev
    restart: "no"
    user: "${svc_user}"
    group_add:
${socket_groups}    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    networks:
      - ddev_default
    external_links:
      - "ddev-router:${NAME}.ddev.site"
    working_dir: ${SET_DIR}
    # ddev eval web (the scoreboard viewer) through the ddev router:
    # VIRTUAL_HOST + *_EXPOSE are ddev's documented seam for exposing a
    # custom service's port - https://${NAME}.ddev.site:8899.
    expose:
      - "8899"
    environment:
      - VIRTUAL_HOST=${NAME}.ddev.site
      - HTTP_EXPOSE=8898:8899
      - HTTPS_EXPOSE=8899:8899
      - ABP_WEB_URL=https://${NAME}.ddev.site:8899
      - DOCKER_HOST=unix:///var/run/docker.sock
      - GEOM_PROBE_DIR=/opt/geom-probe
      - HOME=/tmp/referee-home
      - TZ=${TZ_NAME:-UTC}
      - ABP_PROJECT_DIR=${PROJECT}
      - ABP_EVAL_DIR=${SET_DIR}
    volumes:
      - ${docker_socket}:/var/run/docker.sock:ro
      # ddev execs service commands at /mnt/ddev_config/commands/<service>/
      # inside the target container - without this mount, ddev eval fails
      # with exec 127.
      - ${PROJECT}/.ddev:/mnt/ddev_config:ro
      - ${PROJECT}:${PROJECT}:ro
      - ${PROJECT}/.abp-eval:${PROJECT}/.abp-eval
${extra_mount}      - ${SET_DIR}/runs:${SET_DIR}/runs
    command: ["sleep", "infinity"]
networks:
  ddev_default:
    external: true
EOF
    if cmp -s "$TMP_COMPOSE" "$COMPOSE_FILE" 2>/dev/null; then
      rm -f "$TMP_COMPOSE"
      # Unchanged file is not a running service: a first restart that
      # failed (the ddev-router health-check timeout is a known flake)
      # leaves the compose on disk with no container behind it, and a
      # re-run must not report that as ready (review finding).
      if [ "$(docker inspect -f '{{.State.Running}}' "ddev-${NAME}-abp-eval" 2>/dev/null)" = "true" ]; then
        note "eval service compose unchanged, service running"
        ok_compose=true
      elif command -v ddev >/dev/null 2>&1; then
        note "eval service compose unchanged but the service is not running - restarting ddev"
        if (cd "$PROJECT" && ddev restart) >>"$LOG" 2>&1 \
           || [ "$(docker inspect -f '{{.State.Running}}' "ddev-${NAME}-abp-eval" 2>/dev/null)" = "true" ]; then
          ok_compose=true
        else
          note "ddev restart FAILED (log: $LOG) - run: ddev restart"
        fi
      else
        note "eval service compose unchanged but the service is not running - ddev CLI not found, run: ddev restart"
      fi
    else
      mv "$TMP_COMPOSE" "$COMPOSE_FILE"
      note "wrote .ddev/docker-compose.abp-eval.yaml (eval service + web mask)"
      if command -v ddev >/dev/null 2>&1; then
        note "restarting ddev to apply the eval service and web mask"
        if (cd "$PROJECT" && ddev restart) >>"$LOG" 2>&1; then
          ok_compose=true
        elif [ "$(docker inspect -f '{{.State.Running}}' "ddev-${NAME}-abp-eval" 2>/dev/null)" = "true" ]; then
          # The restart's exit code is the router's health check, which
          # times out on a known flake while every container is up
          # (measured on this kit's first install). The service running is
          # the fact that matters here.
          note "ddev restart reported the router health-check timeout, but the eval service is running - continuing"
          ok_compose=true
        else
          note "ddev restart FAILED (log: $LOG) - run: ddev restart"
        fi
      else
        note "ddev CLI not found - run: ddev restart"
      fi
    fi
  fi
else
  note "no referee image - eval service skipped (ddev eval needs it; fix the image build first)"
fi

# --- 4. bed arming: deliberately NOT done here ----------------------------------
# On this kit the arming evidence (.abp-eval/state.json, the bed .env with
# the five-key credential contract) comes from the instrument's own
# nebula-prep.sh, driven by `abp-eval nebula`. It needs the operator
# handover package (credentials + site baseline) that never travels with
# an install, so a fresh install arrives UNARMED by design: `ddev eval
# list` works, `ddev eval grade` prints the arming command until the
# operator runs it. See .drupalaibp/evals/NEBULA-ARM.md.
ABP_SOURCE_SITE="${ABP_SOURCE_SITE:-https://freelygive.io/}"

# --- 5. accurate summary --------------------------------------------------------
note "instrument ready at $CORE"
$ok_image || note "NO referee image - ddev eval cannot run without it (see log above)"
$ok_compose && note "eval service ready: ddev eval runs in-container (host needs only docker + ddev)" \
            || note "NO eval service - fix the notes above, then re-run this script"
$ok_probe || note "geometry checks will fail until geom-probe deps install"
note "bed NOT armed (by design - needs the operator handover): from the project root on the host,"
note "  $SET_DIR/abp-eval nebula -p . --env <handover-env-file> --source-url $ABP_SOURCE_SITE"
note "grade a migration attempt afterwards with: ddev eval grade"
note "docs: .drupalaibp/evals/README.md and NEBULA-ARM.md"
