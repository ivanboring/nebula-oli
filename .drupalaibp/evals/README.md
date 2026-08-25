# Evals

The canvas-migration eval harness on the Nebula kit, laid out the Drupal way:

- **`custom/`** - this project's eval set, committed here. Ships
  `canvas-migration/`: the freelygive.io homepage migration set (dataset,
  calibrated fixtures, site-specific checks). It is the **same set** the
  [canvas-storybook-ai](https://gitlab.com/freelygive/canvas-storybook-ai)
  kit vendors under its `.drupalaibp/evals/custom/` - copied, not forked,
  so the two kits grade identical cases. When one side recalibrates, copy
  the set across; never edit it here alone.
- **`core/`** - the instrument itself (runner, rubric catalogue, generic
  checks, geom-probe, the referee container). Gitignored: fetched by the
  installer from its canonical home, the `drupal/ai_best_practices`
  repository, at the revision pinned in `core.pin`. This repo never carries
  a drifting copy of the referee.
- **`contrib/`** - eval sets from other projects. Gitignored, fetched the
  same way. Empty for now.

## Install

```bash
bash <(curl -fsSL https://project.pages.drupalcode.org/one_line_installer/drupalaibp) \
  https://github.com/ivanboring/nebula-oli --config nebula-evals
```

The `nebula-evals` config does everything the `nebula` config does, plus the
eval setup: it fetches the pinned instrument into `core/`, overlays
`custom/` onto it, builds the referee image, promotes it to the `abp-eval`
DDEV service (`.ddev/docker-compose.abp-eval.yaml`, generated and
machine-specific), masks `.drupalaibp/evals` from the web container, and
keeps the eval tree out of the bed's git history.

What it deliberately does **not** do is arm the bed. A Nebula bed has no
local Drupal: the migration deploys to a remote Drupal Canvas site (Acquia
Source), and the arming evidence comes from a credential handover that never
travels with an install. See `NEBULA-ARM.md`.

## Grade

```bash
ddev eval list       # all cases, grouped by surface - works on a fresh install
ddev eval grade      # score the current state - no AI, no cost (needs an armed bed)
ddev eval view       # interactive scoreboard browser (terminal)
ddev eval web        # browser viewer, served through the ddev router at
                     #   https://<project>.ddev.site:8899
```

A board reports two numbers: the quality score, and the validity gates
(plumbing). A failed gate makes the run INVALID - it never subtracts from
quality.

`ddev eval` is a service command: it executes inside the `abp-eval`
service, the referee container promoted to a ddev service (python, node,
chromium, agent-browser and a docker CLI are baked into its image), so the
host needs only docker and ddev. `ddev exec` does not forward host shell
environment - pass operator overrides as leading arguments instead:

```bash
ddev eval ABP_PAGE_STORY_ID=pages-home--default grade
```

The graded (paid) migration run is host-driven through the instrument's
front door, `abp-eval nebula` - `ddev eval run` prints the command.

## What this kit grades, and what it cannot

Nebula has no Storybook and no in-bed capture pipeline, so 12 of the 45
cases (the workspace-artifact cases: pipeline output, story files, the tsc
baseline) are skipped by `abp-eval nebula` - the board records the
selection. The build plane is graded instead through the kit's own
`canvas-workbench preview-build`, built inside the web container and served
by the instrument with the remote-asset proxy. Site-state and served-page
cases grade the remote site named in `.env`.

## Isolation from the graded agent

The graded agent works inside the web container (`ddev claude`, the
project-isolated config home under `.ddev/claude-code/`); the graders and
the calibrated fixtures must not be readable from there. Three mechanisms,
all independent:

- the generated compose file mounts a tmpfs over `.drupalaibp/evals` in
  the **web service only**, so the directory appears empty to the agent
  while the host and the `abp-eval` service see the real tree;
- `finalize-evals.sh` keeps the eval tree, the arming state and the
  credential dir out of the bed's **git history** (`.gitignore` before the
  baseline commit) - anything ever committed is readable via `git show`
  regardless of the mask;
- only the `abp-eval` service holds the **docker socket**; the web
  container never does.

## Development

Point the instrument at a local checkout instead of the pin
(composer path-repo style):

```bash
ABP_CORE_DIR=~/projects/ai_best_practices bash .drupalaibp/setup-evals.sh
ddev eval grade
```

The checkout is selected at setup time, not per grade: setup-evals.sh bakes
its path into the generated compose file and restarts ddev. To switch back
to the pin, re-run setup-evals.sh without `ABP_CORE_DIR`. Development mode
grades the checkout's own set, not `custom/`; on fetched instruments the
overlay makes pinned boards report `dirty=true` - the manifest says so.

Every scoreboard records which instrument revision graded it (`abp_git_sha`
plus a dirty flag in the run manifest).
