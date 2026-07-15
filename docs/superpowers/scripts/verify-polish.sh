#!/usr/bin/env bash
# Static invariants for the ops-hub-polish change.
# Usage: bash docs/superpowers/scripts/verify-polish.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=flushit-ops-hub.html
DEPLOY=index.html
FAIL=0
ok()  { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=1; }

echo "── A. Type scale ──"
SMALL=$(grep -o 'font-size:[0-9]\+px' "$SRC" | grep -o '[0-9]\+' | awk '$1<11' | wc -l | tr -d ' ')
[ "$SMALL" = "0" ] && ok "no font-size below 11px" || bad "$SMALL declarations still below 11px"
FRAC=$(grep -c 'font-size:[0-9]\+\.[0-9]\+px' "$SRC" || true)
[ "$FRAC" = "0" ] && ok "no fractional font-size" || bad "$FRAC fractional font-size declarations"

echo "── B. Contrast token ──"
grep -q -- '--td:#757270' "$SRC" && ok "--td is #757270" || bad "--td is not #757270"
grep -q -- '--td:#B8B2A6' "$SRC" && bad "old --td #B8B2A6 still present" || ok "old --td gone"

echo "── C. Video rename ──"
grep -q 'saveDraftName' "$SRC" && bad "saveDraftName still referenced" || ok "saveDraftName gone"
SVN=$(grep -c 'saveVideoName' "$SRC" || true)
[ "$SVN" -ge 3 ] && ok "saveVideoName present ($SVN refs: 1 def + 2 call sites)" || bad "saveVideoName has $SVN refs, expected >=3"

echo "── D. Realtime ──"
grep -q 'PK_COL' "$SRC" && ok "PK_COL map present" || bad "PK_COL map missing"
grep -q '_selfWrites' "$SRC" && ok "_selfWrites present" || bad "_selfWrites missing"
grep -q 'stillInteracting' "$SRC" && ok "stillInteracting present" || bad "stillInteracting missing"

echo "── E. Toasts ──"
CALLS=$(grep -v '^[[:space:]]*//' "$SRC" | grep -c 'toast(' || true)
[ "$CALLS" = "21" ] && ok "21 toast lines (20 call sites + 1 definition)" || bad "$CALLS toast lines, expected 21"
PERSIST=$(grep -c 'toast(.*, *true)' "$SRC" || true)
[ "$PERSIST" = "13" ] && ok "13 persisting error toasts" || bad "$PERSIST persisting toasts, expected 13"
grep -q "toast('● Live')" "$SRC" && bad "'● Live' toast still present" || ok "'● Live' toast gone"

echo "── F. Integrity ──"
diff -q "$SRC" "$DEPLOY" >/dev/null 2>&1 && ok "index.html identical to source" || bad "index.html differs from source"
S=$(grep -n '<script>' "$SRC" | tail -1 | cut -d: -f1)
E=$(grep -n '</script>' "$SRC" | tail -1 | cut -d: -f1)
TMP=$(mktemp /tmp/opshub-XXXXXX.js)
awk -v s="$S" -v e="$E" 'NR>s && NR<e' "$SRC" > "$TMP"
node --check "$TMP" 2>/dev/null && ok "node --check passes" || bad "node --check FAILS"
rm -f "$TMP"

echo ""
[ "$FAIL" = "0" ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
