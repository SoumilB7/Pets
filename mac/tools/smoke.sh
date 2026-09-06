#!/bin/zsh
# Smoke test: build, launch the dev bundle, let it live for a while, then assert on the log
# and the state stream. Exit 0 = all checks passed. Run from anywhere.
#
#   tools/smoke.sh            # ~35 s
#   SMOKE_SECONDS=90 tools/smoke.sh
#
# It restores whatever copy was running before (installed app or nothing).
set -u
cd "$(dirname "$0")/.."
SECS=${SMOKE_SECONDS:-35}
LOG=~/Library/Logs/PixelPet.log
STATE=~/Library/Application\ Support/PixelPet/state.jsonl
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi }

WAS=$(pgrep -x PixelPet | head -1 | xargs -I{} ps -o command= -p {} 2>/dev/null | sed 's|/Contents/MacOS/PixelPet||')
echo "▶ build"
if ! ./build-app.sh >/tmp/pixelpet-build.log 2>&1; then echo "build failed:"; grep error /tmp/pixelpet-build.log; exit 1; fi
ok "build"

pkill -x PixelPet 2>/dev/null; sleep 0.5
# the test needs Normal mode (decisions, heartbeats); remember the user's mode and put it back
USER_MODE=$(defaults read com.soumil.pixelpet mode 2>/dev/null || echo 0)
defaults write com.soumil.pixelpet mode -int 0
STATE_LINES_BEFORE=$( [ -f "$STATE" ] && wc -l < "$STATE" || echo 0 )
echo "▶ launch + run for ${SECS}s"
nohup ./build/PixelPet.app/Contents/MacOS/PixelPet >/dev/null 2>&1 &
sleep 2
check "exactly one instance running"            '[ "$(pgrep -x PixelPet | wc -l | tr -d " ")" = 1 ]'
# a second launch must not create a second pet
nohup ./build/PixelPet.app/Contents/MacOS/PixelPet >/dev/null 2>&1 & sleep 1.5
check "single-instance guard holds"             '[ "$(pgrep -x PixelPet | wc -l | tr -d " ")" = 1 ]'
sleep $SECS
check "still running after ${SECS}s (no crash)" 'pgrep -x PixelPet >/dev/null'

cp "$LOG" build/smoke.log      # keep this run's log; relaunching the installed app rotates the live one
echo "▶ log checks ($LOG → build/smoke.log)"
check "log has launch header"                   'grep -q "\[app\] PixelPet .* started" "$LOG"'
check "desktops detected or explicitly absent"  'grep -q "\[space\] desktops:\|desktop API unavailable" "$LOG"'
check "at least one window scan"                'grep -q "\[scan\]" "$LOG"'
check "context sampled"                         'grep -q "\[context\]" "$LOG"'
check "state sampled"                           'grep -q "\[state\]" "$LOG"'
check "at least one decision"                   'grep -q "\[decide\]" "$LOG"'
check "no warn lines"                           '! grep -q "\[warn\]" "$LOG"'
check "launch header is the new format (version)" 'grep -q "\[app\] PixelPet .* started · pid" "$LOG"'
check "context is never raw loginwindow"        '! grep -q "\[context\] loginwindow" "$LOG"'
check "position heartbeats present"             '[ "$(grep -c "\[pos\]" "$LOG")" -ge 3 ]'
check "no pet stuck (pos heartbeat differs)"    '[ "$(grep "\[pos\]" "$LOG" | sed "s/.*x=\([0-9-]*\).*/\1/" | sort -u | wc -l | tr -d " ")" != 1 ] || [ "$(grep -c "\[pos\]" "$LOG")" -lt 2 ]'

check "state space refreshed at least once"     'grep -q "\[state-space\] refreshed" "$LOG"'
check "a window was captured and embedded"      'grep -q "\[embed\]" "$LOG"'
check "no state-space failures"                 '! grep -q "state-space refresh failed" "$LOG"'

echo "▶ state stream ($STATE)"
check "state file grew"                         '[ "$(wc -l < "$STATE")" -gt "$STATE_LINES_BEFORE" ]'
check "last state line is valid JSON with pet+user" 'tail -1 "$STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"pet\"][\"activity\"] and \"desktop\" in d[\"user\"]"'

echo "▶ mind core (headless)"
check "embed → store → link unit test"          'tools/test-mind.sh >/tmp/pixelpet-mind.log 2>&1'

echo "▶ sprites"
check "all pets validate"                       'python3 tools/preview.py --check >/dev/null'

echo
echo "passed $PASS, failed $FAIL"
pkill -x PixelPet 2>/dev/null; sleep 0.3
defaults write com.soumil.pixelpet mode -int "$USER_MODE"
if [ -n "$WAS" ] && [ -d "$WAS" ]; then open "$WAS"; echo "restored $WAS"; fi
[ $FAIL -eq 0 ]
