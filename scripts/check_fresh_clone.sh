#!/usr/bin/env bash
# Verify this repo actually works for someone who just cloned it.
#
# The whole premise of hotc_examples is that the generated artifacts are checked
# in, so an example builds with no hotc present. That premise is easy to break
# by accident and impossible to notice locally, because the source tree
# regenerates the missing file and your working copy has it whether or not git
# does. Three real bugs shipped that way:
#
#   * kan_control_tb.v was never committed -- and `lint` happened to be the FIRST
#     rule in that Makefile, so a plain `make` died on it before doing anything.
#   * user_tb.v, which kan_control_tb.v `include`s, was missing too. Committing
#     the testbench moved the error rather than fixing it.
#   * Tsetlin_hotstate_uart had no Makefile at all, so `make` there failed with
#     "No targets specified and no makefile found".
#
# Every one of those was found by a person trying it, not by reading the tree.
# So this script clones from git -- NOT the working directory -- into a temp dir
# and drives each example the way a newcomer would.
#
#   ./scripts/check_fresh_clone.sh            # fast: default goal, lint, includes
#   ./scripts/check_fresh_clone.sh --synth    # also build a bitstream per example
#   ./scripts/check_fresh_clone.sh --keep     # leave the clone for inspection
#
# --synth needs yosys, nextpnr-himbaechel and gowin_pack on PATH; it skips with
# a notice rather than failing if they are absent, because a missing toolchain
# is not a repo defect. Everything else runs anywhere.

set -uo pipefail

SYNTH=0; KEEP=0
for a in "$@"; do
  case "$a" in
    --synth) SYNTH=1 ;;
    --keep)  KEEP=1 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLONE="$(mktemp -d -t hotc-examples-fresh-XXXXXX)"
trap '[ "$KEEP" = 1 ] && echo "clone kept at $CLONE" || rm -rf "$CLONE"' EXIT

echo "=== cloning $(git -C "$REPO" rev-parse --short HEAD) into a temp dir ==="
git clone -q "$REPO" "$CLONE" || { echo "clone failed"; exit 1; }
echo

fail=0; checks=0
note() { printf '  %-12s %-26s %s\n' "$1" "$2" "${3:-}"; }
ok()   { checks=$((checks+1)); note "PASS" "$1" "${2:-}"; }
bad()  { checks=$((checks+1)); fail=$((fail+1)); note "FAIL" "$1" "${2:-}"; }

# ---- 1. every `include in committed RTL resolves --------------------------
# This is what made the user_tb.v bug survive the first fix: the file was not
# referenced by any Makefile, only from inside another file.
echo "=== includes ==="
missing=0
cd "$CLONE"
while IFS= read -r f; do
  d="$(dirname "$f")"
  while IFS= read -r inc; do
    [ -z "$inc" ] && continue
    [ -e "$d/$inc" ] || { bad "$(basename "$f")" "includes missing '$inc'"; missing=1; }
  done < <(grep -oE '`include[[:space:]]+"[^"]+"' "$f" 2>/dev/null | sed 's/.*"\(.*\)"/\1/')
done < <(git -C "$CLONE" ls-files '*.v' '*.sv')
[ "$missing" = 0 ] && ok 'all include directives resolve'
echo

# ---- 2. each example answers a plain `make`, and lints if it can ----------
echo "=== per-example ==="
for d in "$CLONE"/examples/*/; do
  name="$(basename "$d")"

  if [ ! -f "$d/Makefile" ]; then
    bad "$name" "no Makefile -- plain \`make\` will fail"
    continue
  fi
  out="$(cd "$d" && timeout 300 make 2>&1)"
  if printf '%s' "$out" | grep -qE "No rule to make target|No targets specified|\*\*\* \[.*\] Error|make: \*\*\*"; then
    bad "$name" "default goal: $(printf '%s' "$out" | grep -m1 -E 'No rule|No targets|Error')"
  else
    ok "$name" "default goal"
  fi

  if (cd "$d" && grep -qE '^lint:' Makefile 2>/dev/null); then
    if (cd "$d" && timeout 300 make lint >/dev/null 2>&1); then ok "$name" "make lint"
    else bad "$name" "make lint failed"; fi
  fi
done
echo

# ---- 3. optionally build a real bitstream --------------------------------
if [ "$SYNTH" = 1 ]; then
  echo "=== synthesis (one board per example) ==="
  if ! command -v yosys >/dev/null 2>&1; then
    echo "  SKIP         yosys not on PATH -- not a repo defect"
  else
    for d in "$CLONE"/examples/*/; do
      name="$(basename "$d")"
      mk="$(ls "$d"/Makefile.synth_* 2>/dev/null | head -1)"
      [ -n "$mk" ] || { note "----" "$name" "no synth makefile"; continue; }
      if (cd "$d" && timeout 3600 make -f "$(basename "$mk")" pack >/dev/null 2>&1); then
        bit="$(ls "$d"/*.fs "$d"/*.bit 2>/dev/null | head -1)"
        ok "$name" "$(basename "$mk") -> $(basename "${bit:-bitstream}")"
      else
        bad "$name" "$(basename "$mk") pack failed"
      fi
    done
  fi
  echo
fi

echo "=== $checks check(s), $fail failed ==="
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
