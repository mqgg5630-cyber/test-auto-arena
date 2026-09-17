#!/usr/bin/env bash
# local_check.sh - the ON-MACHINE check on Linux/macOS (the twin of
# code/local_check.ps1, which does this on Windows). Run by the watcher
# (code/watch-linux.sh, systemd --user timer or cron) after it pulls a request.
#
# Sections - same numbering as the PowerShell version, so a log reads the same
# on either OS:
#   1  the repo's own gate list           (code/gates.py)
#   3  the Office deliverables, checked on this machine: sha256 + size, package
#      parts, XML parse, relationship targets, content types, markers, slides
#      (3a-3g; 3h "a real app opens it" is LibreOffice headless on Linux)
#   4  the local plane of the repo's recipe (code/local_loop.py local): install,
#      build with this machine's own venv, verify, write a normalized receipt
#   4b assert the recipe's receipt keys (deck_slides / checker_blocking / ...)
#   4c a real application opened the produced file
#
# Exit 0 = every required check passed, 1 = at least one failed (the watcher
# pushes that verdict back and the agent fixes it).
#
# Usage: bash code/local_check.sh [--recipe office-deck] [--os linux|macos]
#                                 [--skip-local-plane]
set -u -o pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
RECIPE=""
OSNAME="linux"
[ "$(uname -s)" = "Darwin" ] && OSNAME="macos"
SKIP_PLANE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --recipe) RECIPE="$2"; shift 2 ;;
        --os) OSNAME="$2"; shift 2 ;;
        --skip-local-plane) SKIP_PLANE=1; shift ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

PY=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(0)' 2>/dev/null; then
        PY="$cand"; break
    fi
done
[ -z "$PY" ] && { echo "[FAIL] no working python on PATH"; exit 1; }

fail=0
hr() { echo "== $*"; }

# ------------------------------------------------------------------ 1. gates
hr "gates: the repo's pre-push list (code/gates.py)"
if [ -f code/gates.py ]; then
    "$PY" code/gates.py || fail=1
else
    echo "   WARN code/gates.py is missing - gate list skipped"
fi

# ---------------------------------------------------------- 3. deliverables
hr "deliverables: Office files checked on this machine"
if [ -f deliverable/OFFICE_HASHES.json ]; then
    "$PY" - "$REPO" <<'PYEOF' || fail=1
import hashlib, json, os, re, sys, zipfile
import xml.etree.ElementTree as ET

repo = sys.argv[1]
man = json.load(open(os.path.join(repo, 'deliverable', 'OFFICE_HASHES.json'), encoding='utf-8'))
files = man.get('files') or []
print('   %d Office file(s) declared' % len(files))
problems = 0
for item in files:
    rel = item.get('path') or ''
    path = os.path.join(repo, rel.replace('/', os.sep))
    tag = os.path.basename(rel)
    if not os.path.isfile(path):
        print('   FAIL 3a %s is missing' % rel)
        problems += 1
        continue
    blob = open(path, 'rb').read()
    sha = hashlib.sha256(blob).hexdigest()
    want = item.get('sha256') or ''
    if want and sha != want:
        print('   FAIL 3a %s sha256 %s != %s' % (rel, sha[:12], want[:12]))
        problems += 1
        continue
    size_ok = (not item.get('bytes')) or len(blob) == int(item['bytes'])
    if not size_ok:
        print('   FAIL 3a %s size %d != %s' % (rel, len(blob), item.get('bytes')))
        problems += 1
        continue
    print('   OK   3a %s sha256+size match (%d B)' % (tag, len(blob)))
    try:
        z = zipfile.ZipFile(path)
        names = z.namelist()
    except Exception as exc:
        print('   FAIL 3b %s is not a readable package (%s)' % (tag, exc))
        problems += 1
        continue
    kind = (item.get('kind') or '').lower()
    need = ['[Content_Types].xml']
    need += ['word/document.xml'] if kind == 'docx' else ['ppt/presentation.xml']
    missing = [n for n in need if n not in names]
    if missing:
        print('   FAIL 3b %s is missing part(s): %s' % (tag, missing))
        problems += 1
        continue
    print('   OK   3b %s package parts present' % tag)
    bad_xml = []
    for n in names:
        if n.endswith('.xml') or n.endswith('.rels'):
            try:
                ET.fromstring(z.read(n))
            except Exception as exc:
                bad_xml.append('%s (%s)' % (n, exc))
    if bad_xml:
        print('   FAIL 3c %s has %d unparsable xml part(s): %s' % (tag, len(bad_xml), bad_xml[:3]))
        problems += 1
    else:
        print('   OK   3c %s every xml/rels part parses (%d)' % (tag, len(names)))
    dangling = []
    for n in names:
        if not n.endswith('.rels') or n == '_rels/.rels':
            continue
        base = os.path.dirname(os.path.dirname(n))
        try:
            root = ET.fromstring(z.read(n))
        except Exception:
            continue
        for rel in root:
            target = rel.get('Target') or ''
            if not target or target.startswith('http') or target.startswith('#'):
                continue
            joined = os.path.normpath(os.path.join(base, target)).replace(os.sep, '/')
            if not any(nm == joined for nm in names):
                dangling.append('%s -> %s' % (n, target))
    if dangling:
        print('   FAIL 3d %s has dangling relationship(s): %s' % (tag, dangling[:3]))
        problems += 1
    else:
        print('   OK   3d %s relationship targets all resolve' % tag)
    ct = z.read('[Content_Types].xml').decode('utf-8', 'replace')
    uncovered = [n for n in names
                 if not n.endswith('.rels') and n != '[Content_Types].xml'
                 and ('.' + n.rsplit('.', 1)[-1]) not in ct and n not in ct]
    if uncovered:
        print('   WARN 3e %s: %d part(s) not covered by [Content_Types].xml' % (tag, len(uncovered)))
    else:
        print('   OK   3e %s [Content_Types].xml covers every part' % tag)
    text = ''
    for n in names:
        if n.endswith('.xml') and n.startswith(('ppt/slides/', 'word/')):
            text += z.read(n).decode('utf-8', 'replace')
    for needle in item.get('must_contain') or []:
        if str(needle) in text:
            print("   OK   3f %s contains '%s'" % (tag, needle))
        else:
            print("   FAIL 3f %s is missing '%s'" % (tag, needle))
            problems += 1
    if kind == 'pptx':
        slides = len([n for n in names if re.match(r'ppt/slides/slide\d+\.xml$', n)])
        least = int(item.get('min_slides') or 0)
        if slides >= least:
            print('   OK   3g %s has %d slide(s) >= %d' % (tag, slides, least))
        else:
            print('   FAIL 3g %s has %d slide(s) < %d' % (tag, slides, least))
            problems += 1
print('   %s: %d deliverable problem(s)' % ('FAIL' if problems else 'OK', problems))
sys.exit(1 if problems else 0)
PYEOF
else
    echo "   WARN deliverable/OFFICE_HASHES.json is not present - 3a-3g skipped"
fi

# ------------------------------------------------------- 3h. real app opens
hr "3h: a real application opens the declared files"
if command -v soffice >/dev/null 2>&1 || command -v libreoffice >/dev/null 2>&1; then
    SOFFICE="$(command -v soffice || command -v libreoffice)"
    TMPD="$(mktemp -d)"
    opened=0
    if [ -f deliverable/OFFICE_HASHES.json ]; then
        while IFS= read -r rel; do
            [ -z "$rel" ] && continue
            [ -f "$rel" ] || continue
            if "$SOFFICE" --headless --norestore --convert-to pdf --outdir "$TMPD" "$rel" >/dev/null 2>&1; then
                echo "   OK   3h $SOFFICE opened $rel"
                opened=$((opened + 1))
            else
                echo "   FAIL 3h $SOFFICE refused $rel"
                fail=1
            fi
        done < <("$PY" - <<'PYEOF'
import json, sys
try:
    man = json.load(open('deliverable/OFFICE_HASHES.json', encoding='utf-8'))
except Exception:
    sys.exit(0)
for item in man.get('files') or []:
    print(item.get('kind') == 'docx' and item.get('path') or '')
PYEOF
)
    fi
    [ "$opened" -eq 0 ] && echo "   WARN 3h found no docx deliverable to open with $SOFFICE (skipped)"
    rm -rf "$TMPD"
else
    echo "   WARN 3h no LibreOffice on this machine - open test counted as SKIP"
fi

# --------------------------------------------------- 4. the recipe's local plane
hr "4: the task's local plane (code/local_loop.py local)"
if [ "$SKIP_PLANE" = "1" ]; then
    echo "   .. 4a skipped (--skip-local-plane)"
else
    # the recipe owns the task: it says what to install, what to build and what
    # the receipt must say. This harness only runs it and judges the receipt.
    if [ -f code/local_loop.py ]; then
        echo "   .. 4a running the recipe's local plane"
        "$PY" code/local_loop.py local --os "$OSNAME" ${RECIPE:+--recipe "$RECIPE"} || fail=1
    else
        echo "   WARN code/local_loop.py is missing - falling back to the raw scripts"
        [ -f code/pptmaster_local.sh ] && { bash code/pptmaster_local.sh --repo "$REPO" || fail=1; }
    fi
fi

# ------------------------------------------------------------------ 4b/4c
REC_TXT="results/status/local_loop_receipt.txt"
if [ -f "$REC_TXT" ]; then
    hr "4b the recipe receipt this machine wrote"
    cat "$REC_TXT"
    if grep -q '^loop-ok' "$REC_TXT"; then
        echo "   OK   4b every declared key matched"
    else
        echo "   FAIL 4b the receipt says the task did not verify"
        fail=1
    fi
    OPENED="$(grep -o 'opened=[^ ]*' "$REC_TXT" | tail -1 || true)"
    case "$OPENED" in
        opened=yes|opened=ok*) echo "   OK   4c a real application opened the file ($OPENED)" ;;
        opened=na|opened=skip*|opened=unknown)
            echo "   WARN 4c no application open test on this machine ($OPENED) - structural checks stand" ;;
        '')  echo "   WARN 4c no open result in the receipt - structural checks stand" ;;
        *)   echo "   FAIL 4c the file could not be opened by a real application ($OPENED)"; fail=1 ;;
    esac
else
    echo "   WARN 4b/4c no local_loop_receipt.txt (the local plane did not run)"
fi

# ------------------------------------------------------------------ verdict
if [ "$fail" -eq 0 ]; then
    echo "== local checks passed"
else
    echo "== local checks FAILED"
fi
exit $fail
