#!/usr/bin/env bash
#
# tools/build.sh - build + install the FragFeedback mutator into the local
# UT2004 copy (Windows edition driven through Wine).
#
# What it does (idempotent - safe to run repeatedly):
#   1. syncs source/FragFeedback/Classes/*.uc into $UT2004_DIR/FragFeedback/Classes
#   2. edits [Editor.EditorEngine] / EditPackages in UT2004.ini:
#        - collapses duplicate EditPackages=GTAThirdPerson lines (seen 10x)
#        - ensures exactly one EditPackages=FragFeedback
#   3. compiles with "ucc make" (Wine) => System/FragFeedback.u
#   4. generates the mutator cache   => System/FragFeedback.ucl ("ucc exportcache")
#   5. installs the localization file => System/FragFeedback.int
#
# Requirements: wine with access to the game's drive mapping (default prefix,
# the game path is mapped as Z:\ when the game was installed on this machine).
#
set -euo pipefail

UTDIR="${UT2004_DIR:-/home/jdmr/Juegos/UT2004}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="FragFeedback"

echo "==> game   : $UTDIR"
echo "==> source : $ROOT/source/$PKG/Classes"

# --- 1) sync classes (wipe first: stale renamed classes must not linger) -----
rm -rf "$UTDIR/$PKG/Classes"
mkdir -p "$UTDIR/$PKG/Classes"
cp -f "$ROOT/source/$PKG/Classes/"*.uc "$UTDIR/$PKG/Classes/"

# --- 2) EditPackages bookkeeping --------------------------------------------
python3 - "$UTDIR/System/UT2004.ini" "$PKG" <<'PY'
import re, sys, io
path, pkg = sys.argv[1], sys.argv[2]
with io.open(path, 'r', encoding='latin-1', errors='replace') as fh:
    text = fh.read()

# find the [Editor.EditorEngine] section heading (case-insensitive)
m = re.search(r'^\[Editor\.EditorEngine\]\s*$', text, re.M | re.I)
if not m:
    print("ERROR: [Editor.EditorEngine] not found in UT2004.ini", file=sys.stderr)
    sys.exit(1)

start = m.end()
end = re.search(r'^\[\w[\w.]*\]\s*$', text[start:], re.M)
end = start + end.start() if end else len(text)
block = text[start:end]

# collapse duplicate package entries (keeps the first occurrence of each name)
lines = block.splitlines(True)
seen, kept, dropped, last_edit = set(), [], 0, -1
for idx, ln in enumerate(lines):
    p = re.match(r'^(\s*EditPackages\w*)(\s*=\s*)(\S+)\s*$', ln, re.I)
    if p:
        name = p.group(3).strip()
        if name.lower() in seen:
            dropped += 1
            continue
        seen.add(name.lower())
        if p.group(1).lower() == 'editpackages':
            last_edit = len(kept)
    kept.append(ln)
block = ''.join(kept)

if pkg.lower() not in seen:
    # insert right after the last EditPackages line (keeps the section tidy)
    kept.insert(last_edit + 1, f"EditPackages={pkg}\n")
block = ''.join(kept)

text = text[:start] + block + text[end:]
with io.open(path, 'w', encoding='latin-1', errors='replace') as fh:
    fh.write(text)
print(f"EditPackages ok ({dropped} duplicate lines dropped)")
PY

# --- 3) compile --------------------------------------------------------------
# ucc make in this engine build can consider the package "up to date" even
# after the classes change (seen when renaming a class), so always rebuild
# the single package from scratch.
rm -f "$UTDIR/System/$PKG.u"
cd "$UTDIR/System"
wine UCC.exe make 2>&1 | grep -Ev "fixme:|wineboot|winediag" || true
test -f FragFeedback.u || { echo "ERROR: FragFeedback.u was not produced"; exit 1; }
echo "==> compiled: $UTDIR/System/FragFeedback.u"

# --- 4) mutator cache (.ucl) ---------------------------------------------------
wine UCC.exe exportcache FragFeedback.u 2>&1 | grep -Ev "fixme:|wineboot|winediag" || true
test -f FragFeedback.ucl || echo "WARN: FragFeedback.ucl not produced (Object= line in the .int covers the mutator lists)"

# --- 5) localization file ------------------------------------------------------
cp -f "$ROOT/install/FragFeedback.int" "$UTDIR/System/FragFeedback.int"

echo "==> installed: FragFeedback.u / .ucl(?) / .int in $UTDIR/System"
echo "==> done. Pick the mutator (GTA V Frag Feedback) and press [Configure Mutators]."
