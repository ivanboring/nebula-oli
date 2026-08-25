#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# ddev_started (weight 5, after fetch-nebula.sh).
#
# One Line Installer clones this config repo to provision the new project,
# which leaves the scaffolded project carrying this template's git history and
# origin remote. Replace it with a fresh, origin-less repo so the scaffolded
# project starts clean. Idempotent via a marker file so a re-run never wipes
# commits the user has since made.
set -euo pipefail

marker=".ddev/.drupalaibp-scaffolded"

if [ -e "$marker" ]; then
  echo "Git already reinitialized for this project (found $marker); skipping."
  exit 0
fi

echo "Reinitializing git repository..."
rm -rf .git
git init -q -b main

mkdir -p .ddev
touch "$marker"
