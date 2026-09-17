#!/usr/bin/env bash
# handoff_linux.sh - print the EXACT block the user must paste into a Bash shell
# on their Linux/macOS machine. The twin of agent-handoff.sh (which prints the
# PowerShell block for Windows) - same reason to exist: the block is the only
# bridge to that machine, and hand-written ones keep being wrong (sandbox paths,
# another session's branch, a clone folder that already exists).
#
# Linux specifics that are NOT the Windows flow:
#   * the machine side is code/watch-linux.sh + code/bootstrap-linux.sh
#     (bootstrap.ps1 / watch.ps1 are PowerShell and will not run there)
#   * if this Linux lives INSIDE the Windows box (WSL: same hostname, prompt
#     like user@LAPTOP-xxxx:~/...), PowerPoint is unreachable - 4c falls back to
#     LibreOffice headless, or reports opened=na. Say so in the request.
#   * one clone = one branch = one watcher name, so this can coexist with the
#     Windows loop on the same laptop.
#
# Usage:
#   bash code/handoff_linux.sh                 # print the block
#   bash code/handoff_linux.sh --json          # machine readable
#   bash code/handoff_linux.sh --dir NAME      # suggested clone folder
#   bash code/handoff_linux.sh --parent DIR    # where the clone goes (default ~/projects)
#
# Exit: 0 printed, 1 unusable repo/config, 3 config branch != HEAD (fix first).
set -u -o pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

CFG="skills/git-sync/sync.config.json"
JSON=0
FOLDER=""
PARENT='$HOME/projects'
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=1; shift ;;
        --dir) FOLDER="$2"; shift 2 ;;
        --parent) PARENT="$2"; shift 2 ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,19\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

cfg_key() {
    [ -f "$CFG" ] || return 0
    python3 - "$CFG" "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding='utf-8-sig')).get(sys.argv[2], ''))
except Exception:
    pass
PY
}
HEAD_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ -z "$HEAD_BRANCH" ] && { echo "[ERROR] not a git repository" >&2; exit 1; }
BRANCH="$(cfg_key branch)"
REMOTE="$(cfg_key remote)"; [ -z "$REMOTE" ] && REMOTE="origin"
[ -z "$BRANCH" ] && BRANCH="$HEAD_BRANCH"

URL="$(git remote get-url "$REMOTE" 2>/dev/null)"
if [ -z "$URL" ]; then
    echo "[ERROR] this clone has no remote '$REMOTE' (remotes: $(git remote | tr '\n' ' '))" >&2
    echo "        git remote add $REMOTE https://github.com/<user>/<repo>.git" >&2
    exit 1
fi
REPO_NAME="$(basename "$URL" .git)"
SHORT="${BRANCH#arena/}"; SHORT="${SHORT%%-*}"
[ -z "$FOLDER" ] && FOLDER="${REPO_NAME}-${SHORT}"

if [ "$BRANCH" != "$HEAD_BRANCH" ]; then
    echo "[REFUSED] sync.config.json branch=$BRANCH but HEAD is $HEAD_BRANCH" >&2
    echo "          the watcher would poll a branch nobody pushes to." >&2
    exit 3
fi

PUSHED="yes"
git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1 || PUSHED="no"

if [ "$JSON" = 1 ]; then
    python3 - "$URL" "$BRANCH" "$FOLDER" "$PUSHED" "$REPO_NAME" "$PARENT" <<'PY'
import json, sys
url, branch, folder, pushed, repo, parent = sys.argv[1:7]
print(json.dumps({"url": url, "branch": branch, "folder": folder,
                  "parent": parent, "branch_pushed": pushed == "yes", "repo": repo},
                 ensure_ascii=False))
PY
    exit 0
fi

echo "== paste this on YOUR Linux/macOS machine (Bash) - generated, do not retype"
echo
cat <<EOF
\`\`\`bash
mkdir -p $PARENT && cd $PARENT
git clone -b $BRANCH $URL $FOLDER
cd $FOLDER
bash code/bootstrap-linux.sh            # checks tools/auth + registers the watcher (systemd --user / cron / nohup)
bash code/bootstrap-linux.sh --status   # watcher active, ahead/behind 0/0, last verdict
bash code/watch-linux.sh --once         # OPTIONAL: answer one round right now instead of waiting
\`\`\`
EOF
echo
cat <<EOF
   repo      : $REPO_NAME ($URL)
   branch    : $BRANCH  (pushed to $REMOTE: $PUSHED)
   clone     : $PARENT/$FOLDER   (a NEW folder - never overwrite an existing clone)
   watcher   : systemd --user local-loop-$FOLDER  (or cron/nohup - bootstrap says which)
EOF

if [ "$PUSHED" = "no" ]; then
    cat <<EOF

[NOTE] $REMOTE/$BRANCH does not exist yet - push first:
   bash skills/git-sync/scripts/agent-sync.sh "feat: ..."
EOF
fi

cat <<EOF

if the skill is not in that repo yet (a fresh repo, not this one), add one line
before the bootstrap:
   bash skills/office-loop/agent-install.sh --os linux   # idempotent

already cloned this branch before? then instead of the clone:
   cd $FOLDER && git pull --ff-only && bash code/bootstrap-linux.sh

WSL note: if that Linux shell is the WSL inside the Windows laptop, PowerPoint is
unreachable from it - install libreoffice in WSL, or expect 4c/opened=na and say
so in the request. Two loops on one laptop are fine: this clone registers its own
watcher name and polls its own branch.
EOF
