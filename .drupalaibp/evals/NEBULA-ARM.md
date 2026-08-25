# Arming a Nebula bed: operator handover

A `nebula-evals` install gives you the instrument, the referee service and
the read-only commands. It does not give you an **armed bed**, and that is
structural: this kit deploys to a remote Drupal Canvas site (Acquia
Source), so arming needs the site's credentials and its frozen baseline, a
package that never travels with an install. This page is the contract for
that handover and the one command that consumes it.

## What the operator hands you

The package travels by scp or DM, **never** chat, issue, or commit:

1. **The env file** - the five keys below, plain `KEY=VALUE`, no shell
   syntax. `CANVAS_JSONAPI_PREFIX=api` (Acquia Source) may ride along.
2. **The site's baseline keep-list(s)** - `acquia-baseline-*.json`, the
   frozen pristine-site inventory the sweep verifies against. Drop them
   into the fetched instrument's `harness/` directory
   (`.drupalaibp/evals/core/evals/canvas-migration/harness/`). Re-running
   `setup-evals.sh` after a `core.pin` bump replaces `core/` - copy them
   back in afterwards.

| Key | Plane | What it unlocks |
|---|---|---|
| `CANVAS_SITE_URL` | API | The site's canonical (cms) host. Canvas config API, JSON:API, the site MCP at `<url>/mcp` - component push, page create/publish. Also what Workbench proxies. |
| `CANVAS_CLIENT_ID` | API | The site's own OAuth consumer (client-credentials). |
| `CANVAS_CLIENT_SECRET` | API | Same consumer. |
| `ABP_SERVED_SITE_URL` | page | The **friendly host** real visitors see, behind Acquia's `site_access` password shield. Every served-page check grades this host. |
| `ABP_SERVED_SHIELD_PASSWORD` | page | Unlocks the shield: the checks mint a session cookie and browse as a visitor would. |

Why five keys and not three: a *page* request on the cms host with the
bearer renders the Acquia Source **editor shell** (a 264px sidebar), not
the page a visitor sees; every pixel measured there is shifted, and a
calibration made through it once inverted a centering verdict. Page facts
come from `ABP_SERVED_SITE_URL` + shield cookie, API facts from
`CANVAS_SITE_URL` + bearer. A bed missing the two `ABP_SERVED_*` keys
cannot grade the page plane at all - `nebula-prep.sh` refuses to arm it.

Handling rules (enforced, not advisory): `chmod 600` the file the moment
it lands; never commit it or paste values anywhere; `cm38_secrets_clean`
fails any run that leaks a value into the workspace. The instrument copies
the file to the bed's `.env` (mode 0600, gitignored by Nebula) - the same
file `ddev canvas-setup` would have written, so the canvas CLI and
Workbench use the same connection the graders do.

## One command

From the project root on the host (this is `ddev eval run`'s answer too):

```bash
.drupalaibp/evals/core/evals/canvas-migration/abp-eval nebula \
  -p . --env /path/to/handover.env --source-url https://freelygive.io/
```

Without `--reset-verified` this is free and safe to repeat: it recognises
the bed as the nebula-oli shape (`.ddev/config.workbench.yaml`), validates
the env file through the whitelist parser, installs it as `.env`, restarts
the Workbench daemon on the new connection, seeds `.abp-eval/state.json`
(the arming evidence `ddev eval grade` gates on), trusts the in-container
agent's config home, and then **stops** with the two pending items:

- **LOGIN PENDING** - the agent runs inside the web container under the
  project-isolated config home `.ddev/claude-code/.claude`. It takes the
  credential from the container home at launch (the installer mirrors your
  host login there; if there is none, `ddev claude`, `/login` once,
  `/exit`).
- **RESET PENDING** - the remote site must be at its frozen baseline before
  a graded run (below).

`ddev eval grade` works from this point on: it scores the bed's current
state, no AI, no cost. On a freshly armed bed that is a RUN INVALID board
(nothing migrated yet) - the free way to prove the plumbing before paying.

## The paid run

```bash
.drupalaibp/evals/core/evals/canvas-migration/abp-eval nebula \
  -p . --env /path/to/handover.env --source-url https://freelygive.io/ --reset-verified
```

`--reset-verified` is the operator attestation that `acquia-reset.sh`
exited 0 for this site since the last episode, and it confirms the paid
run (roughly $30-50 and an hour, model pinned by the instrument). The
migration agent runs **in the web container** (`CANVAS_CLAUDE_LOCATION=ddev`,
OS-confined, the operator's personal config never loads), with the 12
workspace-only cases skipped; grading follows immediately and the board
lands under `core/evals/canvas-migration/runs/`. Browse it with
`ddev eval view` or `ddev eval web`.

## Site discipline (the site is shared and remote)

There is no local reset on this kit - not of the site, and not of the bed:

- **One episode per install.** A migration leaves its build in the
  workspace (`src/`, `pages/`); the instrument marks the bed consumed and
  refuses a second graded run on it. The next episode is a fresh
  `nebula-evals` install into a new directory.
- **One episode per sweep.** The site is returned to its frozen baseline by
  the operator-run sweep, `harness/acquia-reset.sh`, never by improvised
  deletes. Run it without `--yes` first (a free, read-only plan), read the
  plan, then with `--yes`:

  ```bash
  bash .drupalaibp/evals/core/evals/canvas-migration/harness/acquia-reset.sh /path/to/handover.env         # plan
  bash .drupalaibp/evals/core/evals/canvas-migration/harness/acquia-reset.sh /path/to/handover.env --yes   # sweep
  ```

  It needs the baseline keep-list in the instrument's `harness/` dir (no
  matching baseline is a hard, correct refusal) and writes a full
  pre-delete rollback record (`acquia-prereset-*.json`) - keep those.
- **Never sweep while a run is in flight.** The plan is live-minus-baseline,
  which mid-run *is* the agent's work.
- `harness/acquia-preflight.sh /path/to/handover.env` proves the whole lane
  (auth on both planes, JSON:API writes enabled, MCP reachable) for free
  before anything paid fires.

## What differs from the canvas-storybook kit

Same cases, same instrument revision, same source page - the comparison is
fair by construction, with these known asymmetries the board records:

- No Storybook and no in-bed capture pipeline: 12 workspace-artifact cases
  are skipped; the build plane is graded through the kit's own
  `canvas-workbench preview-build` instead of a Storybook story.
- No local Drupal: the deploy target is always remote, so there is no
  local-arm board for this kit.
- The bed profile labels the run `canvas-workbench kit (ddev)`; the same
  template run as a plain npm scaffold (no ddev, host-isolated agent) is
  labelled `(npm, no ddev)` - a different measurement environment, kept
  distinct on purpose.
