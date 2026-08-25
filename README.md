# Nebula in DDEV — One Line Installer config

Scaffold [Nebula](https://github.com/acquia/nebula) — Acquia's template for
[Drupal Canvas Code Components](https://project.pages.drupalcode.org/canvas/code-components)
— into a containerized [DDEV](https://ddev.readthedocs.io) project, with
[Canvas Workbench](https://project.pages.drupalcode.org/canvas/code-components/workbench/)
running as a daemon at `https://<project>.ddev.site:5173`.

This repository is a **config source** for the
[One Line Installer](https://www.drupal.org/project/one_line_installer)
(`drupalaibp`): the installer clones it, reads `.drupalaibp/nebula.json`, and
builds the project. The pattern follows
[canvas-storybook-ai](https://gitlab.com/freelygive/canvas-storybook-ai)'s
non-Drupal (`is_drupal: false`) setup.

## Install

```bash
bash <(curl -fsSL https://project.pages.drupalcode.org/one_line_installer/drupalaibp) \
  <URL-of-this-repository> --config nebula
```

Options:

- `--yolo` — unattended, take every default (skips the interactive Canvas
  connection wizard; run `ddev canvas-setup` later)
- `--name <name>` — set the install directory and DDEV project name

To test a local working copy, force `--config-url` with the **absolute path**
to this repo (commit first — the installer git-clones it, so it only sees
committed content):

```bash
bash <(curl -fsSL https://project.pages.drupalcode.org/one_line_installer/drupalaibp) \
  --config-url /absolute/path/to/nebula-oli --config nebula
```

## What you get

- **Nebula, fetched from upstream at install time** (`git clone --depth 1` of
  `acquia/nebula`, overridable with `NEBULA_REPO` / `NEBULA_REF` in the
  environment) — the scaffolded project is the real template, not a vendored
  fork: Canvas CLI, ESLint/Prettier config, Husky pre-commit hook, example
  components, and the `.agents/skills/` Canvas + Nebula agent skills (with
  `.claude/skills/` symlinks already in place).
- **Canvas Workbench as a DDEV daemon** on port 5173, supervised so it
  survives restarts and comes back on plain `ddev start` — no installer
  re-run needed (`.ddev/config.workbench.yaml` owns all per-start setup).
- **Claude Code in the web container** (`ddev claude`).
- **Playwright chromium** in a DDEV global-cache mount (shared across
  projects), with the DDEV CA trusted inside the container so headless Chrome
  can load `https://*.ddev.site` pages.
- **A clean git repository**: the scaffold replaces this repo's history and
  origin with a fresh, origin-less repo and stages the finished project as a
  single baseline commit.
- **An optional Canvas connection**: the install finishes with the interactive
  `ddev canvas-setup` wizard, which writes `.env` for a hosted Acquia Source
  site or any Drupal site running the `canvas_oauth` module. Skip it and
  re-run `ddev canvas-setup` whenever you have the credentials —
  `npx canvas validate` / `pull` / `push` then work against that site.

## After the install

```sh
ddev launch :5173         # open Canvas Workbench (/ on the main URL redirects there)
ddev workbench-restart    # restart the Workbench daemon if it stops responding
ddev npm run code:check   # prettier + eslint
ddev claude               # the coding agent, in the container
ddev canvas-setup         # (re)write .env for a Drupal Canvas site
```

Canvas credentials live in `.env`, which is gitignored and never committed —
the baseline is staged before the connection wizard writes it.

## How it works

`nebula.json` declares a non-Drupal DDEV `php` project, so the whole clone of
this repo is overlaid into the new project **before** the first `ddev start`,
bringing the tracked `.ddev/` files:

- `config.workbench.yaml` — Node 22, the Workbench daemon, router port 5173
  (http 5172), and post-start hooks that install npm deps + chromium and keep
  the daemon healthy on every start. It also sets
  `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=.ddev.site`: Workbench is a Vite dev
  server, and Vite rejects the router's `*.ddev.site` Host header without it.
- `web-build/Dockerfile.workbench` — chromium OS deps and `certutil`.
- `commands/web/` — `ddev canvas-setup` and `ddev workbench-restart`.

The one-time scaffold steps ride on installer events as `.drupalaibp/` hooks,
and are deleted from the finished project:

```
ddev_started
  ├─ w3  fetch-nebula.sh       (web)  clone acquia/nebula into the project,
  │                                   name it after the DDEV site, append DDEV
  │                                   notes to AGENTS.md + README.md
  ├─ w5  reinit-git.sh         (web)  fresh origin-less git repo
  └─ w9  install-deps.sh       (web)  npm ci, chromium, start the daemon
                                      (after the git re-init so Husky's
                                      prepare hook lands on the fresh repo)

before_announce_complete
  ├─ w10 finalize-project.sh   (web)  drop .drupalaibp/, stage the baseline
  └─ w20 hosted-canvas-setup.sh (host) interactive `ddev canvas-setup` → .env
```

The first `ddev start` runs before Nebula lands, so the post-start npm block is
guarded on `package.json` and no-ops; `install-deps.sh` does the first install
explicitly. Every later `ddev start` is covered by the post-start hooks alone.

The scaffolded project keeps Nebula's own `README.md` and `AGENTS.md` (each
with a short appended DDEV section) — this file you are reading stays behind in
the config repo only.
