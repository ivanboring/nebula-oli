#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# before_announce_complete (weight 20 — LAST, after hosted-canvas-setup.sh, so
# every installer write and the wizard have already happened).
#
# Final scaffold housekeeping:
#   1. Clear installer artifacts: .drupalaibp/ plus the project-root copies of
#      the hook scripts the installer stages there to run them (they have all
#      run by now; bash keeps an open fd, so this script deleting itself is
#      safe).
#   2. Correct the origin-remote note the installer appends to AGENTS.md — it
#      assumes the config-repo clone kept its history, but reinit-git.sh
#      replaced it with a fresh, origin-less repo.
#   3. Commit the fully set-up project as a single baseline on that fresh
#      repo, so the user has a clean diff base. --no-verify: Husky's
#      lint-staged must not reformat installer-written files during the
#      scaffold commit. .env is gitignored by Nebula, so the wizard's
#      credentials are never committed.
# Idempotent: skips the commit if the repo already has commits.
set -euo pipefail

echo "Clearing installer artifacts..."
rm -rf .drupalaibp/
rm -f ./fetch-nebula.sh ./reinit-git.sh ./install-deps.sh ./hosted-canvas-setup.sh ./finalize-project.sh

if [ -f AGENTS.md ]; then
  perl -pi -e 's/Its \.git history and `origin` remote are already configured[^\n]*/The install re-initialized it as a fresh git repository with no origin remote — add your own remote before pushing./' AGENTS.md
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "No git repository found; skipping baseline commit." >&2
  exit 0
fi

if [ -n "$(git log --oneline -1 2>/dev/null)" ]; then
  echo "Repository already has commits; skipping baseline commit."
  exit 0
fi

echo "Committing initial scaffold baseline..."
git add -A
git -c user.name="One Line Installer" -c user.email="drupalaibp@localhost" \
  commit -q --no-verify -m "Initial scaffold: Nebula in DDEV with Canvas Workbench" \
  || echo "Baseline commit failed — the scaffold is staged; commit it yourself." >&2
