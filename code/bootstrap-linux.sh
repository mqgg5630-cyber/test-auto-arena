#!/usr/bin/env bash
# bootstrap-linux.sh - the ON-MACHINE setup for Linux/macOS, i.e. the twin of
# bootstrap.ps1 -Auto. Run it once in the clone on the machine that should do
# the local work (and again after moving the clone or changing the branch).
#
#   == 1 checkout        : is this a git clone, on the branch the config names?
#   == 2 tools           : git, bash, python3 (+ a real application for 4c: soffice)
#   == 3 auth            : can this machine read AND push the branch silently?
#   == 4 watcher         : register the poller - systemd --user, else cron, else nohup
#   == 5 state           : handshake/receipt/log of the last round
#
# Several loops may live on one machine (one per repo/branch - e.g. one per
# account): the watcher name defaults to local-loop-<folder>, so nothing clashes.
#
# Usage: bash code/bootstrap-linux.sh [--status] [--register] [--unregister]
#                                     [--once] [--name SLUG]
#                                     [--method auto|systemd|cron|nohup]
#                                     [--interval SECONDS] [--branch B] [--remote R]
# Default (no flag) = --register --status, i.e. what bootstrap.ps1 -Auto does.
#
# Exit: 0 ok, 1 a required check failed, 2 refused (repo/config says otherwise).
set -u -o pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

DO_STATUS=0; DO_REGISTER=0; DO_UNREGISTER=0; DO_ONCE=0; EXPLICIT_ACTION=0
NAME=""; METHOD="auto"; INTERVAL=120
BRANCH=""; REMOTE="origin"
while [ $# -gt 0 ]; do
    case "$1" in
        # the four below are ACTIONS; --name/--method/--interval/--branch/--remote
        # are modifiers, and on their own they mean "register" (never a silent no-op)
        --status) DO_STATUS=1; EXPLICIT_ACTION=1; shift ;;
        --register) DO_REGISTER=1; EXPLICIT_ACTION=1; shift ;;
        --unregister) DO_UNREGISTER=1; EXPLICIT_ACTION=1; shift ;;
        --once) DO_ONCE=1; EXPLICIT_ACTION=1; shift ;;
        --name) NAME="$2"; shift 2 ;;
        --method) METHOD="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,19\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done
[ "$EXPLICIT_ACTION" = 0 ] && { DO_REGISTER=1; DO_STATUS=1; }
[ "$DO_REGISTER$DO_UNREGISTER$DO_STATUS$DO_ONCE" = "0000" ] && DO_STATUS=1

FAILED=0
say()  { echo "$*"; }
ok()   { echo "OK   $*"; }
warn() { echo "WARN $*"; }
bad()  { echo "FAIL $*"; FAILED=1; }

CFG="skills/git-sync/sync.config.json"
cfg_key() {  # $1 = key (tolerates the UTF-8 BOM PowerShell writes)
    [ -f "$CFG" ] || return 0
    python3 - "$CFG" "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding='utf-8-sig')).get(sys.argv[2], ''))
except Exception:
    pass
PY
}

# ---------------------------------------------------------------- 1. checkout
say "== 1. checkout"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    bad "not a git clone: $REPO"
    exit 2
fi
HEAD_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ -z "$BRANCH" ] && BRANCH="$(cfg_key branch)"
if [ -z "$BRANCH" ]; then
    BRANCH="$HEAD_BRANCH"
    warn "$CFG has no branch key - using HEAD ($BRANCH)"
elif [ "$BRANCH" != "$HEAD_BRANCH" ]; then
    bad "config says branch=$BRANCH but HEAD is $HEAD_BRANCH"
    echo "     the watcher would poll a branch nobody pushes to."
    echo "     fix $CFG (or: bash code/bootstrap-linux.sh --branch $HEAD_BRANCH) and re-run."
    exit 2
fi
ok "clone: $REPO"
ok "branch: $BRANCH"
URL="$(git remote get-url "$REMOTE" 2>/dev/null || true)"
if [ -z "$URL" ]; then
    bad "no remote '$REMOTE' (remotes: $(git remote | tr '\n' ' '))"
    exit 2
fi
ok "remote: $REMOTE -> $URL"
[ -z "$NAME" ] && NAME="$(basename "$REPO" | tr -cd 'A-Za-z0-9._-')"  # tr -d also eats the newline

# ------------------------------------------------------------------- 2. tools
say "== 2. tools"
for t in git bash python3; do
    if command -v "$t" >/dev/null 2>&1; then
        ok "$t: $(command -v "$t")"
    else
        bad "$t not on PATH"
    fi
done
if command -v python3 >/dev/null 2>&1; then
    PYV="$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo '?')"
    case "$PYV" in
        3.[0-7].*|2.*) bad "python3 is $PYV - the local plane needs 3.8+" ;;
        *) ok "python3 version: $PYV" ;;
    esac
fi
SOFFICE="$(command -v soffice || command -v libreoffice || true)"
if [ -n "$SOFFICE" ]; then
    ok "a real application to open files (3h/4c): $SOFFICE"
else
    warn "no soffice/libreoffice - 4c will report opened=na (install libreoffice to get a real open check)"
fi
[ "$(uname -s)" = "Darwin" ] && ok "system: macOS ($(sw_vers -productVersion 2>/dev/null || echo '?'))" \
                             || ok "system: $(uname -s) $(uname -r)"

# -------------------------------------------------------------------- 3. auth
say "== 3. auth"
if git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1; then
    ok "read: $REMOTE/$BRANCH is visible"
else
    if git ls-remote --exit-code "$REMOTE" >/dev/null 2>&1; then
        warn "read ok, but $REMOTE/$BRANCH does not exist yet (push it from the sandbox first)"
    else
        bad "cannot reach $REMOTE (credentials? network?)"
    fi
fi
DRY="$(GIT_TERMINAL_PROMPT=0 git push --dry-run "$REMOTE" "HEAD:refs/heads/$BRANCH" 2>&1)"
if [ $? -eq 0 ]; then
    ok "push: silent push to $REMOTE/$BRANCH works"
else
    if printf '%s' "$DRY" | grep -qiE 'terminal prompts disabled|authentication failed|could not read Username|Permission denied'; then
        bad "push needs credentials this shell cannot give"
        echo "     fix (one of):  gh auth login        /  git config --global credential.helper store"
        echo "     then: git push $REMOTE HEAD:refs/heads/$BRANCH   (should succeed silently)"
    else
        warn "push dry-run said: $(printf '%s' "$DRY" | tail -1)"
    fi
fi

# ----------------------------------------------------------------- 4. watcher
have_systemd() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user show-environment >/dev/null 2>&1 || return 1
    return 0
}
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="local-loop-$NAME"
LOG="$HOME/.local-loop-$NAME.log"
PIDFILE="$HOME/.local-loop-$NAME.pid"
CRON_TAG="# git-sync local loop: $NAME"

register_systemd() {
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/$UNIT.service" <<EOF
[Unit]
Description=git-sync local loop ($NAME: pull request, run code/local_check.sh, push verdict)
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$REPO
ExecStart=/usr/bin/env bash code/watch-linux.sh --once --branch $BRANCH --remote $REMOTE
TimeoutStartSec=2400
Nice=10
EOF
    cat > "$UNIT_DIR/$UNIT.timer" <<EOF
[Unit]
Description=git-sync local loop timer ($NAME)

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Unit=$UNIT.service

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload >/dev/null 2>&1
    systemctl --user enable --now "$UNIT.timer" >/dev/null 2>&1 || return 1
    ok "watcher: systemd --user $UNIT.timer (every 2 min, survives reboot)"
    echo "     log: journalctl --user -u $UNIT.service -f"
}

register_cron() {
    command -v crontab >/dev/null 2>&1 || return 1
    TMP="$(mktemp)"
    crontab -l 2>/dev/null | sed "/^# >>> $CRON_TAG/,/^# <<< $CRON_TAG/d" > "$TMP"
    {
        echo "# >>> $CRON_TAG"
        echo "*/2 * * * * cd $REPO && /usr/bin/env bash code/watch-linux.sh --once --branch $BRANCH --remote $REMOTE >> $LOG 2>&1"
        echo "# <<< $CRON_TAG"
    } >> "$TMP"
    crontab "$TMP" 2>/dev/null || { rm -f "$TMP"; return 1; }
    rm -f "$TMP"
    ok "watcher: cron entry every 2 min (tag: $CRON_TAG)"
    echo "     needs a running cron daemon (WSL: sudo service cron start)"
    echo "     log: $LOG"
}

register_nohup() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        ok "watcher: already running (pid $(cat "$PIDFILE"))"
        return 0
    fi
    ( setsid nohup bash code/watch-linux.sh --interval "$INTERVAL" --branch "$BRANCH" --remote "$REMOTE" \
        >> "$LOG" 2>&1 & echo $! > "$PIDFILE" ) >/dev/null 2>&1 || return 1
    sleep 1
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        ok "watcher: background loop, pid $(cat "$PIDFILE") (every ${INTERVAL}s)"
        warn "this one does NOT survive a reboot - re-run this script after one"
        echo "     log: tail -f $LOG"
        return 0
    fi
    return 1
}

unregister() {
    if [ -f "$UNIT_DIR/$UNIT.timer" ]; then
        systemctl --user disable --now "$UNIT.timer" >/dev/null 2>&1 || true
        rm -f "$UNIT_DIR/$UNIT.service" "$UNIT_DIR/$UNIT.timer"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        ok "removed systemd unit $UNIT"
    fi
    if command -v crontab >/dev/null 2>&1; then
        TMP="$(mktemp)"
        crontab -l 2>/dev/null | sed "/^# >>> $CRON_TAG/,/^# <<< $CRON_TAG/d" > "$TMP"
        crontab "$TMP" 2>/dev/null && ok "removed cron entry ($CRON_TAG)"
        rm -f "$TMP"
    fi
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null || true
        rm -f "$PIDFILE"
        ok "stopped background loop"
    fi
}

say "== 4. watcher (name: $NAME)"
if [ "$DO_UNREGISTER" = 1 ]; then
    unregister
fi
if [ "$DO_REGISTER" = 1 ]; then
    done_reg=0
    case "$METHOD" in
        auto)
            if have_systemd && register_systemd; then done_reg=1
            elif register_cron; then done_reg=1
            elif register_nohup; then done_reg=1
            fi ;;
        systemd) register_systemd && done_reg=1 ;;
        cron)    register_cron && done_reg=1 ;;
        nohup)   register_nohup && done_reg=1 ;;
        *) bad "unknown --method $METHOD"; done_reg=1 ;;
    esac
    [ "$done_reg" != 1 ] && bad "could not register a watcher (systemd/cron/nohup all unavailable?)"
fi
if [ "$DO_ONCE" = 1 ]; then
    say "== running one poll now"
    bash code/watch-linux.sh --once --branch "$BRANCH" --remote "$REMOTE" || warn "that poll exited non-zero (see the log it wrote for the round)"
fi

# ------------------------------------------------------------------- 5. state
if [ "$DO_STATUS" = 1 ]; then
    say "== 5. state"
    STATE="$(systemctl --user is-active "$UNIT.timer" 2>/dev/null || true)"
    [ -n "$STATE" ] && echo "     systemd $UNIT.timer: $STATE"
    if command -v crontab >/dev/null 2>&1; then
        crontab -l 2>/dev/null | grep -q "$CRON_TAG" && echo "     cron: registered ($CRON_TAG)"
    fi
    [ -f "$PIDFILE" ] && echo "     background loop pid: $(cat "$PIDFILE" 2>/dev/null)"
    AHEAD="$(git rev-list --count "$REMOTE/$BRANCH..HEAD" 2>/dev/null || echo '?')"
    BEHIND="$(git rev-list --count "HEAD..$REMOTE/$BRANCH" 2>/dev/null || echo '?')"
    echo "     ahead/behind vs $REMOTE/$BRANCH: $AHEAD/$BEHIND"
    if [ -f results/status/handshake.json ]; then
        python3 - <<'PY' 2>/dev/null || true
import json
d = json.load(open('results/status/handshake.json', encoding='utf-8-sig'))
print("     handshake: round=%s request=%s local=%s" % (
    d.get('round'), d.get('request_state') or d.get('state'), d.get('local_state')))
PY
    fi
    LAST_LOG="$(ls -t results/status/check_r*.txt 2>/dev/null | head -1 || true)"
    if [ -n "$LAST_LOG" ]; then
        echo "     last verdict: $LAST_LOG"
        tail -2 "$LAST_LOG" | sed 's/^/       /'
    else
        echo "     no verdict on this machine yet - the sandbox has to push a request first"
    fi
    if [ -f results/status/local_loop_receipt.txt ]; then
        echo "     last receipt: $(tail -1 results/status/local_loop_receipt.txt)"
    fi
fi

echo
if [ "$FAILED" = 1 ]; then
    echo "[FAILED] fix the FAIL lines above - the round would not survive them."
    exit 1
fi
echo "[OK] this machine is ready: it polls $REMOTE/$BRANCH every 2 min and answers the rounds it finds."
echo "     agent side: push a request, then read the verdict with agent-check.sh --read"
exit 0
