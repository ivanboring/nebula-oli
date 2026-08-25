#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# before_announce_complete (weight 10).
#
# Final scaffold housekeeping, after Nebula, skills and the agent denylist are
# all in place:
#   1. Clear installer artifacts (.drupalaibp/) from the scaffolded project.
#   2. Stage the fully set-up project as the baseline on the fresh repo
#      reinit-git.sh created; the installer completes the baseline commit, so
#      the user has a clean diff base.
# Idempotent: skips the staging if the repo already has commits.
set -euo pipefail

echo "Clearing installer artifacts..."
rm -rf .drupalaibp/

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "No git repository found; skipping baseline staging." >&2
  exit 0
fi

if [ -n "$(git log --oneline -1 2>/dev/null)" ]; then
  echo "Repository already has commits; skipping baseline staging."
  exit 0
fi

echo "Staging initial scaffold baseline..."
git add -A
