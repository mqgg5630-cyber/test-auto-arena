#!/usr/bin/env bash
# watch-linux.sh - the ON-MACHINE watcher on Linux/macOS, i.e. the twin of
# watch.ps1 + the Windows Scheduled Task.
#
# On Windows the bridge (skills/git-sync) registers a scheduled task that polls
# the branch; on Linux/macOS the same job is a systemd --user timer (or a cron
# entry - both templates ship in skills/office-loop/templates/). This script is
# what that timer runs:
#
#   1. fetch the branch; read results/status/handshake.json from the REMOTE
#   2. if the remote asks for a round this machine has not answered yet:
#        - pull (fast-forward only - a dirty worktree is reported, never clobbered)
#        - run code/local_check.sh with a timeout
#        - write results/status/check_r<round>_<timestamp>.txt
#        - set local_state=passed|failed in the handshake
#        - commit + push (only these files + whatever the checks produced)
#   3. otherwise do nothing and exit 0 (the timer runs often; that is cheap)
#
# Exit 0 = nothing to do or the round was answered. 1 = the push failed (the
# agent will see no verdict and must look at the log this script leaves behind).
#
# Usage: bash code/watch-linux.sh [--branch B] [--remote origin] [--once]
#                                [--interval 120] [--timeout 1800]
set -u -o pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

BRANCH=""
REMOTE="origin"
INTERVAL=0
TIMEOUT=1800
while [ $# -gt 0 ]; do
    case "$1" in
        --branch) BRANCH="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --once) shift ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done
if [ -z "$BRANCH" ] && [ -f skills/git-sync/sync.config.json ]; then
    BRANCH="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
              skills/git-sync/sync.config.json | head -1)"
fi
[ -z "$BRANCH" ] && BRANCH="$(git rev-parse --abbrev-ref HEAD)"
ORIGIN="$REMOTE/$BRANCH"
HS="results/status/handshake.json"

say() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

json_field() {  # $1 = json text, $2 = key
    printf '%s' "$1" | python3 -c "import json,sys;d=json.loads(sys.stdin.buffer.read().decode('utf-8-sig'));print(d.get('$2',''))" 2>/dev/null
}

answer_round() {
    local round="$1" remote_state="$2"
    local stamp logfile
    stamp="$(date '+%Y%m%d-%H%M%S')"
    logfile="results/status/check_r${round}_${stamp}.txt"
    mkdir -p results/status
    say "round $round: pulling"
    if ! git pull --ff-only "$REMOTE" "$BRANCH" >/dev/null 2>&1; then
        say "round $round: pull failed (local commits or dirty worktree?) - skipped"
        echo "check round $round on $(hostname) - pull failed" > "$logfile"
        git add -A "$logfile" 2>/dev/null
        git commit -q -m "check: round $round pull failed on this machine" 2>/dev/null && \
            git push "$REMOTE" "$BRANCH" --quiet 2>/dev/null
        return 0
    fi
    say "round $round: running code/local_check.sh (timeout ${TIMEOUT}s)"
    {
        echo "check round $round on $(hostname) - started"
        echo "cmd: bash code/local_check.sh"
        echo "started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo
    } > "$logfile"
    local start end code
    start="$(date +%s)"
    set +e
    timeout "$TIMEOUT" bash code/local_check.sh >> "$logfile" 2>&1
    code=$?
    set -e
    end="$(date +%s)"
    local state='failed'
    [ "$code" -eq 0 ] && state='passed'
    {
        echo
        echo "elapsed: $((end - start))s"
        echo "check round $round on $(hostname) - $state (exit $code)"
    } >> "$logfile"
    python3 - "$HS" "$state" "$round" "$(hostname)" <<'PYEOF'
import datetime, json, sys
path, state, rnd, host = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    d = json.load(open(path, encoding='utf-8-sig'))
except Exception:
    d = {}
d.update({'local_state': state, 'local_updated': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
          'host': host, 'round': int(rnd) if str(rnd).isdigit() else d.get('round')})
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(d, fh, ensure_ascii=False, indent=2)
    fh.write('\n')
PYEOF
    git add -A
    if git diff --cached --quiet; then
        say "round $round: nothing changed"
    else
        git -c user.name='git-sync watcher' -c user.email='watcher@localhost' \
            commit -q -m "check: round $round $state"
        if git push "$REMOTE" "$BRANCH" --quiet; then
            say "round $round: verdict pushed ($state)"
        else
            say "round $round: PUSH FAILED - the agent will not see this verdict"
            return 1
        fi
    fi
    return 0
}

poll_once() {
    git fetch "$REMOTE" "$BRANCH" --quiet 2>/dev/null || { say "fetch failed"; return 0; }
    local remote_hs asked answered round
    remote_hs="$(git show "$ORIGIN:$HS" 2>/dev/null || true)"
    [ -z "$remote_hs" ] && { say "no handshake on $ORIGIN yet"; return 0; }
    asked="$(json_field "$remote_hs" round)"
    answered="$(json_field "$remote_hs" local_updated)"
    round="$asked"
    local local_hs=''
    [ -f "$HS" ] && local_hs="$(cat "$HS")"
    if [ -n "$answered" ] && [ "$(json_field "$local_hs" round)" = "$asked" ]; then
        return 0   # already answered this round
    fi
    say "round $round: requested on $ORIGIN, not answered here yet"
    answer_round "$round" "$(json_field "$remote_hs" arena_state)"
}

say "watcher: repo=$REPO branch=$BRANCH remote=$REMOTE"
if [ "$INTERVAL" -gt 0 ]; then
    while true; do poll_once || true; sleep "$INTERVAL"; done
else
    poll_once
fi
