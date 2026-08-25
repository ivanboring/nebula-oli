#!/usr/bin/env bash
# Usage: link-integrity.sh <url> <spec_file> <case_id>
# Link-integrity gate (cm32-cm34, seeded by the run-3 cm09 decomposition):
# asserts source-derived link facts against the RENDERED page's anchors,
# via the agent-browser daemon (sandbox: host). Three deterministic
# failure classes run-3 exhibited: dead navigation (every nav anchor
# href="#"), an invented social handle (freelygiveltd -> freelygive), and
# unlinked work tiles (images without anchors).
#
# Hardened after the codex+opus adversarial review (2026-07-17):
# - only VISIBLE anchors count (getClientRects) - planted hidden anchors
#   cannot satisfy any case;
# - pair matching is an origin-constrained regex: href must be the path
#   itself (trailing slash / query / fragment tolerated) or the path on
#   the source origin - https://evil.example/about no longer passes and
#   /about/ no longer false-fails;
# - social handles are exact-path regexes, not substrings - the handle in
#   a query string or freelygiveltdxyz no longer passes;
# - work tiles require /work/<slug>, so bare /work nav links cannot
#   satisfy the tile minimum.
#
# Case kinds (harness/link-spec.json):
#   expected_pairs + origin_pattern - some visible anchor whose text
#       contains T has an href matching ^((origin))?P/?([?#].*)?$
#   forbid_hash_anchors    - zero visible anchors with href '#' or ''
#   required_href_regexes / forbidden_href_regexes
#   min_count_regex        - at least N visible anchors match the regex
#
# Scope-awareness (v1.2 spec): the migration builds the HOMEPAGE ONLY, so
# links to other pages are out of scope and cannot honestly resolve. Any
# assertion prefixed `advisory_` (advisory_expected_pairs,
# advisory_forbid_hash_anchors, advisory_min_count_regex) is checked and
# REPORTED but never fails the run - it is a structure-parity signal for a
# future full-site migration, not a homepage-migration defect.
set -u
url="$1"; specfile="$2"; case_id="$3"
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $1" >&2; exit 1; }

command -v agent-browser >/dev/null 2>&1 || fail "agent-browser not on PATH (host sandbox)"
export AGENT_BROWSER_IGNORE_HTTPS_ERRORS=1
command -v jq >/dev/null 2>&1 || fail "jq not on PATH"
[ -f "$specfile" ] || fail "link spec missing: $specfile"
jq -e --arg c "$case_id" '.cases[$c]' "$specfile" >/dev/null 2>&1 \
  || fail "case '$case_id' not defined in $specfile"

agent-browser set viewport 1440 900 >/dev/null || fail "viewport"
agent-browser open "$url" >/dev/null || fail "open $url"
agent-browser wait 2000
agent-browser eval 'window.scrollTo(0, document.body.scrollHeight)' >/dev/null
agent-browser wait 1500
agent-browser eval 'window.scrollTo(0, 0)' >/dev/null

raw=$(agent-browser eval 'JSON.stringify(Array.from(document.querySelectorAll("a")).filter(function(a){return a.getClientRects().length > 0}).map(function(a){return {href: a.getAttribute("href") || "", text: (a.textContent || "").replace(/\s+/g, " ").trim()}}))') \
  || fail "anchor collection eval errored"
anchors=$(printf '%s' "$raw" | jq -r '.' 2>/dev/null | jq -c '.' 2>/dev/null)
printf '%s' "$anchors" | jq -e 'type == "array"' >/dev/null 2>&1 || fail "anchor collection returned non-JSON: $raw"
total=$(printf '%s' "$anchors" | jq 'length')
[ "$total" -gt 0 ] || fail "page has zero visible anchors - wrong page or render failure"
echo "collected $total visible anchors from $url"

spec=$(jq -c --arg c "$case_id" '.cases[$c]' "$specfile")
failures=""
advisories=""

# expected_pairs: hard when in scope, advisory (structure parity) when the
# pair targets an out-of-scope page (homepage-only migration).
for scope in hard advisory; do
  key="expected_pairs"; [ "$scope" = advisory ] && key="advisory_expected_pairs"
  [ "$(printf '%s' "$spec" | jq --arg k "$key" 'has($k)')" = "true" ] || continue
  origin=$(printf '%s' "$spec" | jq -r '.origin_pattern // ""')
  while IFS=$'\t' read -r text path; do
    ok=$(printf '%s' "$anchors" | jq --arg t "$text" --arg p "$path" --arg o "$origin" \
      '[.[] | select((.text | contains($t)) and (.href | test("^(" + $o + ")?" + $p + "/?([?#].*)?$")))] | length')
    [ "$ok" -gt 0 ] && continue
    if [ "$scope" = advisory ]; then
      advisories="$advisories
  - nav link [text contains '$text'] not carried as -> '$path' (out-of-scope page, not required for a homepage-only migration)"
    else
      failures="$failures
  - no visible anchor [text contains '$text'] -> '$path' (own origin or relative)"
    fi
  done < <(printf '%s' "$spec" | jq -r --arg k "$key" '.[$k][] | @tsv')
done

for scope in hard advisory; do
  key="forbid_hash_anchors"; [ "$scope" = advisory ] && key="advisory_forbid_hash_anchors"
  [ "$(printf '%s' "$spec" | jq --arg k "$key" '.[$k] // false')" = "true" ] || continue
  dead=$(printf '%s' "$anchors" | jq '[.[] | select(.href == "#" or .href == "")] | length')
  [ "$dead" -eq 0 ] && continue
  if [ "$scope" = advisory ]; then
    advisories="$advisories
  - $dead dead visible anchor(s) with href '#'/'' (source has zero) - honest for a homepage-only migration whose nav targets other pages, but the source's hrefs were not carried"
  else
    failures="$failures
  - $dead dead visible anchor(s) with href '#'/'' (source has zero) - navigation goes nowhere"
  fi
done

if [ "$(printf '%s' "$spec" | jq 'has("required_href_regexes")')" = "true" ]; then
  while IFS= read -r rx; do
    ok=$(printf '%s' "$anchors" | jq --arg r "$rx" '[.[] | select(.href | test($r))] | length')
    [ "$ok" -gt 0 ] || failures="$failures
  - no visible anchor href matches '$rx'"
  done < <(printf '%s' "$spec" | jq -r '.required_href_regexes[]')
fi

if [ "$(printf '%s' "$spec" | jq 'has("forbidden_href_regexes")')" = "true" ]; then
  while IFS= read -r rx; do
    bad=$(printf '%s' "$anchors" | jq --arg r "$rx" '[.[] | select(.href | test($r))] | length')
    [ "$bad" -eq 0 ] || failures="$failures
  - $bad anchor(s) match forbidden pattern '$rx' (invented/rewritten link)"
  done < <(printf '%s' "$spec" | jq -r '.forbidden_href_regexes[]')
fi

for scope in hard advisory; do
  key="min_count_regex"; [ "$scope" = advisory ] && key="advisory_min_count_regex"
  [ "$(printf '%s' "$spec" | jq --arg k "$key" 'has($k)')" = "true" ] || continue
  rx=$(printf '%s' "$spec" | jq -r --arg k "$key" '.[$k].regex')
  min=$(printf '%s' "$spec" | jq -r --arg k "$key" '.[$k].min')
  n=$(printf '%s' "$anchors" | jq --arg r "$rx" '[.[] | select(.href | test($r))] | length')
  [ "$n" -ge "$min" ] && continue
  if [ "$scope" = advisory ]; then
    advisories="$advisories
  - only $n visible anchor(s) match '$rx' (source has $min; the linked detail pages are out of scope for a homepage-only migration)"
  else
    failures="$failures
  - only $n visible anchor(s) match '$rx' (source-derived minimum: $min)"
  fi
done

[ -n "$advisories" ] && echo "ADVISORY (homepage-only scope, not scored):$advisories"
if [ -n "$failures" ]; then
  fail "link case '$case_id':$failures"
fi
echo "OK: link case '$case_id' holds"
