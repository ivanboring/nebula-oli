#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# ddev_started (weight 9, after reinit-git.sh).
#
# One-time first install of the Node toolchain. The first `ddev start` ran its
# post-start hooks before Nebula landed (fetch-nebula.sh runs at ddev_started),
# so the guarded npm block in .ddev/config.workbench.yaml was a clean no-op and
# the Workbench daemon is crash-looping without node_modules. Do the same work
# here — deps, Playwright chromium, daemon restart — so the install finishes
# with Workbench up. Every LATER `ddev start` is covered by the post-start
# hooks, not by this script.
#
# Runs after reinit-git.sh on purpose: `npm ci` triggers Nebula's husky
# `prepare` script, which wires the pre-commit hook into the FRESH repo.
set -euo pipefail

if [ ! -f package.json ]; then
  echo "No package.json found; skipping dependency install." >&2
  exit 0
fi

echo "Installing npm dependencies..."
npm ci || npm install

echo "Ensuring Playwright chromium is installed (shared global cache)..."
npx --yes playwright install chromium || true

echo "Starting the Canvas Workbench daemon..."
supervisorctl restart webextradaemons:workbench || true
