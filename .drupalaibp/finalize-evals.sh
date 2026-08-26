#!/usr/bin/env bash
# drupalaibp hook — runs INSIDE the DDEV web container (where=web),
# before_announce_complete (weight 30 — LAST), nebula-evals config ONLY.
#
# Same job as finalize-project.sh (which the evals config replaces in its
# hook list), with one difference: the standard finalizer deletes the whole
# .drupalaibp/ directory, and the eval harness LIVES there - the custom/
# set, the fetched core/ instrument, setup-evals.sh for re-runs, and the
# docs `ddev eval` points at. So installer artifacts are cleared item by
# item and the eval runtime is preserved.
set -euo pipefail

# 1. Installer artifacts. The installer stages the hook scripts into the
#    project root to run them; the canonical copies live in .drupalaibp/.
#    Nebula's own .gitignore replaced this config repo's at fetch time and
#    knows nothing about them, so remove the root copies explicitly (bash
#    keeps an open fd, so this script deleting its own root copy is safe).
echo "Clearing installer artifacts (keeping the eval runtime)..."
rm -f ./fetch-nebula.sh ./reinit-git.sh ./install-deps.sh ./hosted-canvas-setup.sh \
      ./finalize-project.sh ./setup-evals.sh ./finalize-evals.sh
# find, not a glob: dotfiles under .drupalaibp/ must be cleared too.
find .drupalaibp -mindepth 1 -maxdepth 1 -print | while IFS= read -r f; do
  case "$(basename "$f")" in
    evals|nebula-evals.json|setup-evals.sh|finalize-evals.sh) ;;  # keep
    *) rm -rf "$f" ;;
  esac
done

# 2. Origin-remote note: the installer assumes the config-repo clone kept
#    its history, but reinit-git.sh replaced it with a fresh, origin-less repo.
if [ -f AGENTS.md ]; then
  perl -pi -e 's/Its \.git history and `origin` remote are already configured[^\n]*/The install re-initialized it as a fresh git repository with no origin remote — add your own remote before pushing./' AGENTS.md
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "No git repository found; skipping baseline commit." >&2
  exit 0
fi

# 3. Keep the eval tree out of the bed's git history. The web container
#    sees it masked (tmpfs, .ddev/docker-compose.abp-eval.yaml), but a
#    baseline commit made before the mask - or any later in-container
#    commit - would put the datasets, rubrics and calibrated fixtures (the
#    answer key) into a repo the graded agent can read via `git show`. The
#    generated compose file is machine-specific on top of that, .abp-eval/
#    holds the bed's arming state and the run's staging, and
#    .ddev/claude-code/ holds the in-container agent's credential. Belt and
#    braces with the mask: either alone can be absent.
if ! grep -q '^/\.drupalaibp/evals/' .gitignore 2>/dev/null; then
  printf '\n%s\n%s\n%s\n%s\n%s\n' \
    "# Eval harness: never in bed history (the graded agent reads history via git show)." \
    "/.drupalaibp/evals/" \
    "/.ddev/docker-compose.abp-eval.yaml" \
    "/.abp-eval/" \
    "/.ddev/claude-code/" >> .gitignore
  echo "Excluded the eval tree, arming state and agent credential dir from the bed's git history (.gitignore)."
fi

if [ -n "$(git log --oneline -1 2>/dev/null)" ]; then
  echo "Repository already has commits; skipping baseline commit."
  exit 0
fi

# 4. Baseline commit, identical to finalize-project.sh. --no-verify: Husky's
#    lint-staged must not reformat installer-written files during the
#    scaffold commit. .env is gitignored by Nebula, so the wizard's
#    credentials are never committed.
echo "Committing initial scaffold baseline..."
git add -A
git -c user.name="One Line Installer" -c user.email="drupalaibp@localhost" \
  commit -q --no-verify -m "Initial scaffold: Nebula in DDEV with Canvas Workbench + migration evals" \
  || echo "Baseline commit failed — the scaffold is staged; commit it yourself." >&2
