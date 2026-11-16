#!/usr/bin/env bash
# JC-36 tests: private build modes, publish.sh refusal gates (modes + release gate), .gitignore rules,
# and verify-no-secrets.sh against a local mock. Uses PLACEHOLDER secrets in a temp copy only; never the
# real secret-config.json, never the live site, never publishes.
# Usage: bash test/jc36-modes.sh      Needs: bash, python3, jq, curl, node, git.
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); chmod 700 "$T"; A=$T/app; mkdir -p "$A"; MP=""
cleanup(){ [ -n "$MP" ] && kill "$MP" 2>/dev/null; chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; }; trap cleanup EXIT
cp -r "$REPO/src" "$REPO/tools" "$REPO/test" "$REPO/publish.sh" "$A/"; rm -rf "$A/test/node_modules"
PT=placeholdertoken0000000000000000abcd; PC=placeholder_coll_000000000000000000abcd
printf '{"slug":"placeholder-slug-0000","path_token":"%s","collection":"%s"}\n' "$PT" "$PC" > "$A/secret-config.json"; chmod 600 "$A/secret-config.json"
export CAT_HEALTH_DIR=$A
pass=0; failn=0; skip=0
ok(){ echo "PASS: ${1//$PT/<TOKEN>}"; pass=$((pass+1)); }; no(){ echo "FAIL: ${1//$PT/<TOKEN>}"; failn=$((failn+1)); }
leak(){ printf '%s' "$1" | grep -qF -e "$PT" -e "$PC"; }
build(){ python3 "$A/tools/build.py" >/dev/null; }
pub(){ out=$(bash "$A/publish.sh" "$@" 2>&1); rc=$?; }

echo "== 1. build output modes (with a loose umask 022 on purpose)"
(umask 022; build)
for p in site site/.herenow "site/$PT"; do [ "$(stat -c %a "$A/$p")" = 700 ] && ok "$p is 0700" || no "$p is $(stat -c %a "$A/$p")"; done
for p in site/.herenow/data.json "site/$PT/index.html"; do [ "$(stat -c %a "$A/$p")" = 600 ] && ok "$p is 0600" || no "$p mode"; done
[ "$(find "$A/site" -perm /077 | wc -l)" = 0 ] && ok "no group/world bits anywhere under site/" || no "loose paths under site/"

echo "== 2. publish.sh dry run"
PUBLISH_DRY_RUN=1 pub; [ $rc = 0 ] && ok "dry run passes on a private build" || no "dry run rc=$rc"
printf '%s' "$out" | grep -q "RELEASE GATE" && no "dry run called the release gate" || ok "dry run skips the release gate"
leak "$out" && no "dry run output leaked a secret" || ok "dry run output has no raw token/collection"

echo "== 3. publish.sh refuses loosened modes"
loosen(){ build; chmod "$1" "$A/$2"; SKIP_BUILD=1 PUBLISH_DRY_RUN=1 pub
  [ $rc != 0 ] && printf '%s' "$out" | grep -q "NOT publishing" && ok "refuses when $2 is $1" || no "accepted $2 at $1"
  leak "$out" && no "refusal output leaked a secret ($2)"; }
loosen 644 site/.herenow/data.json; loosen 640 site/.herenow/data.json; loosen 644 "site/$PT/index.html"
loosen 755 site; loosen 711 site; loosen 755 site/.herenow; loosen 755 "site/$PT"; loosen 644 site/robots.txt

echo "== 4. check-site-modes.sh fails on its own errors"
build; bash "$A/tools/check-site-modes.sh" >/dev/null 2>&1; [ $? != 0 ] && ok "no arguments -> fails" || no "no-arg call passed"
bash "$A/tools/check-site-modes.sh" "$A" "" >/dev/null 2>&1; [ $? != 0 ] && ok "empty token -> fails" || no "empty token passed"
mkdir -p "$T/shf" "$T/shs"; printf '#!/bin/sh\nexit 1\n' > "$T/shf/find"; printf '#!/bin/sh\nexit 1\n' > "$T/shs/stat"; chmod +x "$T/shf/find" "$T/shs/stat"
PATH="$T/shf:$PATH" bash "$A/tools/check-site-modes.sh" "$A" "$PT" >/dev/null 2>&1; [ $? != 0 ] && ok "find error -> fails" || no "find error passed"
PATH="$T/shs:$PATH" bash "$A/tools/check-site-modes.sh" "$A" "$PT" >/dev/null 2>&1; [ $? != 0 ] && ok "stat error -> fails" || no "stat error passed"
mkdir -p "$A/site/.herenow/locked/deep"; chmod 000 "$A/site/.herenow/locked"
bash "$A/tools/check-site-modes.sh" "$A" "$PT" >/dev/null 2>&1; [ $? != 0 ] && ok "unreadable subfolder (real find error) -> fails" || no "real find error passed"
chmod 700 "$A/site/.herenow/locked"

echo "== 5. release gate wiring"
G=/workspace/releases/tools/release-gate.sh
L_GATE=$(grep -n 'release-gate.sh' "$REPO/publish.sh" | head -1 | cut -d: -f1); L_PUB=$(grep -n 'bash "$PUB"' "$REPO/publish.sh" | head -1 | cut -d: -f1)
[ -n "$L_GATE" ] && [ -n "$L_PUB" ] && [ "$L_GATE" -lt "$L_PUB" ] && ok "gate line runs before the here.now publisher" || no "gate line missing or after publisher"
grep -q 'release-gate.sh cat-health\|"$G" cat-health' "$REPO/publish.sh" && ok "gate called for project cat-health on site/" || no "gate project name"
build; HERENOW_API_KEY=dummy-not-a-key pub; [ $rc = 2 ] && printf '%s' "$out" | grep -q usage && ok "real publish without a version -> refuses (exit 2)" || no "no-version rc=$rc"
if [ -x "$G" ] && [ ! -e /workspace/releases/signoffs/cat-health-v9999.0.0.ok ] && ls -d /home/box/agent-data/plugins/cache/cursor-public/here_now/*/skills/here-now/scripts/publish.sh >/dev/null 2>&1; then
  build; HERENOW_API_KEY=dummy-not-a-key pub 9999.0.0
  [ $rc != 0 ] && printf '%s' "$out" | grep -q "RELEASE GATE BLOCKED" && printf '%s' "$out" | grep -q "Release gate did not pass; NOT publishing" && ! printf '%s' "$out" | grep -q publish_result \
    && ok "unsigned version -> release gate blocks, nothing published" || no "gate did not block (rc=$rc)"
  leak "$out" && no "gate output leaked a secret" || ok "gate output has no raw token/collection"
else echo "SKIP: release gate or here.now publisher not on this machine"; skip=$((skip+1)); fi
build; chmod 644 "$A/site/.herenow/data.json"; SKIP_BUILD=1 HERENOW_API_KEY=dummy-not-a-key pub 9999.0.0
[ $rc != 0 ] && printf '%s' "$out" | grep -q "readable by other accounts" && ! printf '%s' "$out" | grep -q "RELEASE GATE" && ok "real publish stops at the mode gate before the release gate" || no "mode gate order rc=$rc"

echo "== 6. .gitignore and repo leak check"
for f in site/x secret-config.json secret-config.next.json secret-config.prev.json backups/x.json docs/JC-36-rotation-plan.md; do
  git -C "$REPO" check-ignore -q "$f" && ok ".gitignore drops $f" || no "$f not ignored"; done
git -C "$REPO" check-ignore -q secret-config.example.json && no "example config is ignored" || ok "secret-config.example.json stays tracked"
[ -z "$(git -C "$REPO" ls-files docs/JC-36-rotation-plan.md backups site)" ] && ok "rotation plan, backups, site/ not in the repo" || no "private files tracked"
[ -z "$(git -C "$REPO" grep -lF -e "$PT" -e "$PC" -- ':!test/jc36-modes.sh' 2>/dev/null)" ] && ok "repo has no placeholder token/collection" || no "repo grep hit"
[ -z "$(grep -rlF '/workspace/cat-health' "$REPO/publish.sh" "$REPO/tools")" ] && ok "no hardcoded app dir" || no "hardcoded /workspace/cat-health"

echo "== 7. verify-no-secrets.sh"
build; PORT=$((20000 + RANDOM % 20000)); (cd "$A/test" && MOCK_ROOT="$A/site" exec node mock-server.js $PORT >/dev/null 2>&1) & MP=$!
for i in $(seq 50); do curl -s -o /dev/null "http://localhost:$PORT/robots.txt" && break; sleep 0.1; done
out=$(VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" 2>&1); rc=$?
[ $rc = 0 ] && ok "verify passes on the mock" || { no "verify rc=$rc"; printf '%s\n' "$out" | sed "s#$PT#<TOKEN>#g; s#$PC#<COLL>#g"; }
leak "$out" && no "verify stdout leaked raw token/collection" || ok "verify output masks token/collection"
printf '%s' "$out" | grep -q "data.json is 404" && ok "manifest 404 checked" || no "404 check missing"
chmod 644 "$A/site/.herenow/data.json"; VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" >/dev/null 2>&1 && no "verify accepted loose data.json" || ok "verify fails on loose data.json"
build; echo "<p>$PC</p>" > "$A/site/index.html"; chmod 600 "$A/site/index.html"
out=$(VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" 2>&1); [ $? != 0 ] && printf '%s' "$out" | grep -q "LEAKS COLLECTION" && ok "verify fails if the root page has the collection" || no "root leak not caught"
# config/jq problems must exit before any network call: shim curl records any call
CS=$T/curlshim; mkdir -p "$CS"; printf '#!/bin/sh\ntouch %s/curl-called\nexit 7\n' "$T" > "$CS/curl"; chmod +x "$CS/curl"
NJ=$T/nojq; mkdir -p "$NJ"; for d in /usr/local/bin /usr/bin /bin; do for b in "$d"/*; do n=$(basename "$b"); [ "$n" = jq ] || [ -e "$NJ/$n" ] || ln -s "$b" "$NJ/$n"; done; done; ln -sf "$CS/curl" "$NJ/curl"
rm -f "$T/curl-called"; PATH="$NJ" bash "$A/tools/verify-no-secrets.sh" >/dev/null 2>&1; rc=$?
[ $rc != 0 ] && [ ! -e "$T/curl-called" ] && ok "jq missing -> error before any curl" || no "jq missing rc=$rc"
cp "$A/secret-config.json" "$T/cfg.bak"
for bad in '{"slug":"placeholder-slug-0000","path_token":"","collection":"'"$PC"'"}' '{"slug":"placeholder-slug-0000","path_token":"'"$PT"'"}' '{"slug":null,"path_token":"'"$PT"'","collection":"'"$PC"'"}'; do
  printf '%s\n' "$bad" > "$A/secret-config.json"; rm -f "$T/curl-called"
  PATH="$CS:$PATH" bash "$A/tools/verify-no-secrets.sh" >/dev/null 2>&1; rc=$?
  [ $rc != 0 ] && [ ! -e "$T/curl-called" ] && ok "empty/missing config value -> error before any curl" || no "bad config rc=$rc"; done
cp "$T/cfg.bak" "$A/secret-config.json"

echo; echo "TOTAL pass=$pass fail=$failn skip=$skip"; [ $failn = 0 ]
