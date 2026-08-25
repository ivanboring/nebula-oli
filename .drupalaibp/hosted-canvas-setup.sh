#!/usr/bin/env bash
# drupalaibp hook — runs on the HOST (where=host), before_announce_complete
# (weight 10 — before finalize-project.sh, which cleans up this script's
# staged copy afterwards; the .env the wizard writes is gitignored by Nebula,
# so the baseline commit never includes it).
#
# There is no local Drupal site in this build, so the project connects to a
# hosted Drupal Canvas site (e.g. Acquia Source). Run the interactive
# `ddev canvas-setup` wizard as the final setup step, which writes .env. The
# wizard itself offers "set up now / add the data later", so the user can skip
# the prompts and configure it whenever. Interactive-only: auto-skipped when no
# terminal is attached (e.g. --yolo in CI), where `ddev canvas-setup` runs
# later.
set -euo pipefail

# The wizard prompts for a site URL and a client secret — it needs a real
# terminal. /dev/tty is the reliable handle whether the installer was launched
# as `bash <(curl …)` or `curl … | bash`.
if ! { true </dev/tty; } 2>/dev/null || ! { true >/dev/tty; } 2>/dev/null; then
  echo "No terminal attached — skipping canvas-setup." >&2
  echo "Run 'ddev canvas-setup' later to connect to a Drupal Canvas site." >&2
  exit 0
fi

echo
echo "Connecting to a Drupal Canvas site (you can re-run 'ddev canvas-setup' anytime)..."

# Prefer inheriting the terminal directly. Redirecting stdin from /dev/tty
# while ddev also allocates a TTY (docker exec -it) can double-bind the
# terminal and swallow keystrokes, so only fall back to the explicit /dev/tty
# redirect when our own stdio is not already a terminal (e.g. the installer was
# launched via `curl | bash` rather than `bash <(curl …)`).
if [ -t 0 ] && [ -t 1 ]; then
  ddev canvas-setup \
    || echo "canvas-setup did not complete — run 'ddev canvas-setup' later." >&2
else
  ddev canvas-setup </dev/tty >/dev/tty 2>&1 \
    || echo "canvas-setup did not complete — run 'ddev canvas-setup' later." >&2
fi
