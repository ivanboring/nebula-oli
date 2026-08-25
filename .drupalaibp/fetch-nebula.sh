#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# ddev_started (weight 3, before reinit-git.sh).
#
# Fetches the upstream Nebula template (https://github.com/acquia/nebula) into
# the project root, so the scaffolded project tracks upstream instead of
# carrying a vendored fork. Nebula's own README.md, AGENTS.md, CLAUDE.md and
# .gitignore intentionally overwrite this config repo's copies — the project
# should BE Nebula, plus the tracked .ddev/ additions that ride alongside it.
#
# Afterwards the package name is set to the DDEV project name and a short DDEV
# section is appended to AGENTS.md and README.md (CLAUDE.md is just @AGENTS.md).
#
# Idempotent: skips when package.json already exists (i.e. Nebula has landed).
set -euo pipefail

NEBULA_REPO="${NEBULA_REPO:-https://github.com/acquia/nebula}"
NEBULA_REF="${NEBULA_REF:-main}"

if [ -f package.json ]; then
  echo "package.json already present; skipping Nebula fetch."
  exit 0
fi

echo "Fetching Nebula from ${NEBULA_REPO} (${NEBULA_REF})..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 --branch "$NEBULA_REF" "$NEBULA_REPO" "$tmp/nebula"
rm -rf "$tmp/nebula/.git"
cp -a "$tmp/nebula/." .

# Name the project after the DDEV site (what `@drupal-canvas/create` would ask).
name="${DDEV_SITENAME:-}"
if [ -n "$name" ]; then
  echo "Naming the project '${name}'..."
  for f in package.json package-lock.json; do
    [ -f "$f" ] && perl -pi -e "s/\"name\": \"nebula\"/\"name\": \"${name}\"/g" "$f"
  done
fi

# DDEV usage notes, appended to Nebula's own docs. AGENTS.md is what coding
# agents read (Nebula's CLAUDE.md references it); README.md is for humans.
site_host="${DDEV_SITENAME:-my-project}.ddev.site"

cat >> AGENTS.md <<EOF

## DDEV environment

This project runs inside [DDEV](https://ddev.readthedocs.io). Canvas Workbench
is served by a DDEV daemon at https://${site_host}:5173 — from inside the web
container reach it at http://localhost:5173. If it stops responding, restart it
with \`ddev workbench-restart\` (inside the container:
\`supervisorctl restart webextradaemons:workbench\`).

Run npm and the Canvas CLI through DDEV from the host (\`ddev npm run dev\`,
\`ddev exec npx canvas validate\`), or directly when you are inside the web
container. Connect the project to a Drupal Canvas site with
\`ddev canvas-setup\` (writes \`.env\`, which is gitignored), then restart the
Workbench so it picks up the connection.
EOF

cat >> README.md <<EOF

## DDEV

This project was scaffolded into [DDEV](https://ddev.readthedocs.io) by the
One Line Installer. Canvas Workbench runs as a DDEV daemon:

| Command                  | Description                                          |
| ------------------------ | ---------------------------------------------------- |
| \`ddev start\`           | Start the project (Workbench comes up automatically) |
| \`ddev launch :5173\`    | Open Canvas Workbench (https://${site_host}:5173)    |
| \`ddev workbench-restart\` | Restart the Workbench daemon                       |
| \`ddev canvas-setup\`    | Connect to a Drupal Canvas site (writes \`.env\`)    |
| \`ddev npm run code:check\` | Prettier + ESLint checks                          |
| \`ddev claude\`          | Claude Code, inside the web container                |
EOF

echo "Nebula fetched into the project."
