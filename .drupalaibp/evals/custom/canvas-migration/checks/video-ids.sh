#!/usr/bin/env bash
# cm39: the videos the build embeds are the RIGHT videos. Layout (cm15) and
# screenshot checks only prove a video-shaped card exists; a card pointing at
# the wrong YouTube id renders identically and passes both. run-3's agent
# claimed "real video ids confirmed from live DOM" for fre_video_card, but
# nothing verified the claim - this check does.
#
# Ground truth: the freelygive.io homepage embeds exactly three YouTube
# videos. The ids come from the crawl output
# (website-to-components/output/freelygive.io/site-resources.json and the
# frozen source-snapshot/index.html, both agree):
#   99amnw4xk5c, LjdAsguNwJQ, RUI66lKljdE
# They are passed in as the expected set so the check does not depend on the
# crawl output being mounted in the sandbox (same idiom as cm31 source_alts).
#
# Oracle: the SET of YouTube ids across the built page stories equals the
# expected set. This catches all three failure modes a layout/screenshot
# check misses:
#   - a wrong-but-present id (built id not among the source's videos)
#   - a hallucinated id (same)
#   - a dropped video (source id absent from the build)
# Ids are public YouTube identifiers, not secrets, so they are printed as
# evidence.
#
# Generalized 2026-07-20 (was: one hardcoded page file + videoId= props):
#   - The page story filename is agent-chosen (run-3 wrote
#     FreelygiveHome.stories.tsx, the isolated run FreelyGiveHome.stories.tsx),
#     so the check scans a pages DIRECTORY, not one filename. The pristine
#     scaffold example (Home.stories.tsx) embeds no YouTube ids, so set
#     equality over the directory is the same oracle.
#   - The embed prop is also agent-chosen: accept videoId="..." props AND
#     URL forms (watch?v=, youtu.be/, /embed/, /vi/<id>/ thumbnails). All
#     forms feed one id set.
#
# Extension-agnostic (audit A4): the kit template says .stories.jsx, both
# observed agents wrote .tsx - scan *.stories.* so neither false-fails.
#
# Usage: video-ids.sh <workspace-dir> <pages-rel-dir> <expected-ids-csv>
# Sandbox: ddev (web container, cwd /var/www/html).
set -u
ws="${1:?usage: video-ids.sh <workspace-dir> <pages-rel-dir> <expected-ids-csv>}"
pages_rel="${2:?pages dir relative to workspace}"
ids_csv="${3:?expected video ids, comma-separated}"

fail() { echo "FAIL: $1" >&2; exit 1; }

cd "$ws" || fail "workspace not found: $ws"
[ -d "$pages_rel" ] || fail "pages dir not found: $ws/$pages_rel"
ls "$pages_rel"/*.stories.* >/dev/null 2>&1 || fail "no page stories in $ws/$pages_rel"

# Built ids, from any accepted embed form. YouTube ids are >=6 of
# [A-Za-z0-9_-]; the site's are 11.
built=$( {
  grep -hoE "videoId[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9_-]{6,}[\"']" "$pages_rel"/*.stories.* 2>/dev/null \
    | grep -oE "[\"'][A-Za-z0-9_-]{6,}[\"']" | tr -d "\"'"
  grep -hoE "(watch\?v=|youtu\.be/|/embed/|/vi/)[A-Za-z0-9_-]{6,}" "$pages_rel"/*.stories.* 2>/dev/null \
    | grep -oE "[A-Za-z0-9_-]{6,}$"
} | sort -u)
expected=$(printf '%s' "$ids_csv" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' | sort -u)

[ -n "$expected" ] || fail "no expected ids supplied (check wiring)"
[ -n "$built" ] || fail "no video ids found in $ws/$pages_rel/*.stories.* - wrong dir, or every video was dropped"

extra=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$built"))
missing=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$built"))

echo "built ids: $(printf '%s' "$built" | tr '\n' ' ')"
echo "expected:  $(printf '%s' "$expected" | tr '\n' ' ')"

problems=""
[ -z "$extra" ] || problems="$problems
  - wrong/unknown video id on the build (not one of the source's videos): $(printf '%s' "$extra" | tr '\n' ' ')"
[ -z "$missing" ] || problems="$problems
  - source video missing from the build: $(printf '%s' "$missing" | tr '\n' ' ')"

[ -z "$problems" ] || fail "embedded videos do not match the source:$problems"
echo "OK: build embeds exactly the source's videos ($(printf '%s' "$built" | grep -c .) of them)"
