# Arming a Nebula bed

A `nebula-evals` install gives you the kit and referee service. `ddev
canvas-setup` supplies the remote Drupal Canvas credentials, arms the bed
and captures the clean-site baseline in one place. No hand-carried
handover JSON is needed for the normal operator flow.

The credentials still deserve handover discipline: move them by scp or DM,
**never** chat, issue, or commit. Canvas setup writes them to the bed's
gitignored `.env`; no secret belongs in the arming evidence or scoreboard.

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
cannot grade the page plane at all.

Handling rules are enforced, not advisory: never commit credentials or
paste values anywhere; `cm38_secrets_clean` fails any run that leaks a
value into the workspace.

## Run a migration

Install the eval-enabled kit:

```bash
bash <(curl -fsSL https://project.pages.drupalcode.org/one_line_installer/drupalaibp) \
  https://github.com/ivanboring/nebula-oli --config nebula-evals
```

Then, from the new project root:

```bash
ddev canvas-setup
ddev claude-isolated
```

Canvas setup prompts for the Canvas API and served-site credentials plus
the source website shown on the scoreboard. It writes `.env`, restarts
Workbench, arms `.abp-eval/state.json`, trusts the isolated agent workspace
and captures the freshly created Acquia Source site as the sweep baseline.
This setup-time capture is the reliable clean moment; if it cannot reach
the site, setup remains successful and tells you to capture the baseline
before migrating.

Give the isolated agent this migration prompt:

> Recreate https://freelygive.io/ as closely as possible in Drupal Canvas.

Use the isolated config home, not `ddev claude`: the latter loads the
operator's mirrored skills, hooks, agents and history, which is not a
measurement of the kit. When the migration finishes:

```bash
ddev eval grade
ddev eval view
ddev eval export
```

Grade is AI-free and has no cost. The board is grade-only: cost and time
come only from the harness's `-p` envelope, and the delta oracle uses the
frozen setup baseline rather than a pre-agent snapshot. Run one grade at a
time; the referee lock rejects parallel grades because they share browser
and staging state.

## Run it again

First inspect the live-minus-baseline reset plan, then apply it:

```bash
ddev eval sweep
ddev eval sweep --yes
ddev claude-isolated
```

`sweep` without `--yes` is read-only. `sweep --yes` deletes remote residue,
verifies the site against the baseline captured by canvas-setup, and writes
a full pre-delete rollback record to
`.abp-eval/acquia-prereset-<timestamp>.json`. After the reset, give the
isolated agent the migration prompt again and grade the result.

Never sweep while an agent run or grade is in flight. The plan is
live-minus-baseline, which mid-run *is* the agent's work. The grade lock
protects only this bed; it cannot see another process using the shared
remote site.

## Diagnostics / advanced

`ddev eval preflight` proves both auth planes, JSON:API discovery and
writes, and a self-cleaning probe page before a paid run.

`ddev eval capture-baseline [--force]` freezes the **CURRENT** site state as
clean. Normally canvas-setup has already done this. Use the command only
after a setup-time capture failed, or on a fresh template or just-swept
site. It refuses to bless a second baseline unless you delete the existing
file or pass `--force`; force removes the foot-gun guard, not the clean-site
requirement.

The hands-off harness is the only flow that still uses the standalone
arming script:

```bash
.drupalaibp/evals/core/evals/canvas-migration/abp-eval nebula \
  -p . --env /path/to/handover.env --source-url https://freelygive.io/ --reset-verified
```

`--reset-verified` attests that the sweep exited 0 since the last episode
and confirms the paid run. The agent runs in the web container with the
operator's personal config excluded; grading follows automatically. Never
run the harness after a manual episode on the same bed, and never re-arm a
consumed harness bed: it would grade prior work as its own. A new harness
episode needs a fresh install and a verified sweep.

## Site discipline (the site is remote)

There is no local Drupal reset on this kit. The site is returned to its
frozen baseline only by the operator-run sweep, never by improvised
deletes. No matching baseline is a hard, correct refusal. Keep the rollback
records. The harness additionally treats its workspace bed as
single-use: a consumed bed stays consumed even after the remote site is
swept.

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
