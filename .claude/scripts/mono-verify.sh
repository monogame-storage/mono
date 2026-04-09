#!/usr/bin/env bash
# mono-verify: full engine validation pipeline
# Runs scan + coverage + determinism + fuzz + bench on all demos.
# Prints a concise dashboard.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_RUNNER="$REPO_ROOT/editor/templates/mono/mono-test.js"
DEMO_DIR="${1:-$REPO_ROOT/demo}"
FRAMES="${FRAMES:-120}"
FUZZ_RUNS="${FUZZ_RUNS:-50}"
DETERMINISM_RUNS="${DETERMINISM_RUNS:-3}"

if [ ! -f "$TEST_RUNNER" ]; then
  echo "error: mono-test.js not found at $TEST_RUNNER" >&2
  exit 1
fi

if [ ! -d "$DEMO_DIR" ]; then
  echo "error: demo directory not found: $DEMO_DIR" >&2
  exit 1
fi

echo "=== MONO VERIFY ==="
echo "demo dir : $DEMO_DIR"
echo "frames   : $FRAMES"
echo "fuzz     : $FUZZ_RUNS runs/game"
echo "detm     : $DETERMINISM_RUNS runs/game"
echo

# --- 1. SCAN + COVERAGE ---
echo "[1/4] SCAN + COVERAGE"
SCAN_OUT=$(node "$TEST_RUNNER" --scan "$DEMO_DIR" --frames "$FRAMES" --coverage --quiet 2>&1)
SCAN_LINE=$(echo "$SCAN_OUT" | grep -E "^(SCAN:|Used:|Public APIs:)" || true)
echo "$SCAN_OUT" | grep -E "^  [✓✗]" || true
echo
echo "$SCAN_LINE" | sed 's/^/  /'
echo

# Extract list of games that passed
GAMES=$(echo "$SCAN_OUT" | grep -E "^  ✓ PASS" | awk '{print $3}' | sed 's|/game.lua||' || true)
if [ -z "$GAMES" ]; then
  echo "  no passing games, aborting deeper checks"
  exit 1
fi

# --- 2. DETERMINISM per game ---
echo "[2/4] DETERMINISM ($DETERMINISM_RUNS runs each)"
DETM_FAIL=0
for g in $GAMES; do
  GDIR="$DEMO_DIR/$g"
  if [ -f "$GDIR/game.lua" ]; then
    OUT=$(cd "$GDIR" && node "$TEST_RUNNER" game.lua --frames "$FRAMES" --colors 4 --determinism "$DETERMINISM_RUNS" --seed 42 --quiet 2>&1 || true)
    if echo "$OUT" | grep -q "DETERMINISM: PASS"; then
      printf "  ✓ %-30s PASS\n" "$g"
    else
      printf "  ✗ %-30s FAIL\n" "$g"
      DETM_FAIL=$((DETM_FAIL + 1))
    fi
  fi
done
echo

# --- 3. FUZZ per game ---
echo "[3/4] FUZZ ($FUZZ_RUNS runs each)"
FUZZ_CRASH=0
for g in $GAMES; do
  GDIR="$DEMO_DIR/$g"
  if [ -f "$GDIR/game.lua" ]; then
    OUT=$(cd "$GDIR" && node "$TEST_RUNNER" game.lua --frames "$FRAMES" --colors 4 --fuzz "$FUZZ_RUNS" --quiet 2>&1 || true)
    CRASHES=$(echo "$OUT" | grep -oE "Crashes:\s+[0-9]+" | awk '{print $2}' || echo "?")
    if [ "$CRASHES" = "0" ]; then
      printf "  ✓ %-30s 0 crashes\n" "$g"
    else
      printf "  ✗ %-30s %s crashes\n" "$g" "$CRASHES"
      FUZZ_CRASH=$((FUZZ_CRASH + 1))
    fi
  fi
done
echo

# --- 4. BENCH per game ---
echo "[4/4] BENCH"
for g in $GAMES; do
  GDIR="$DEMO_DIR/$g"
  if [ -f "$GDIR/game.lua" ]; then
    OUT=$(cd "$GDIR" && node "$TEST_RUNNER" game.lua --frames "$FRAMES" --colors 4 --bench --quiet 2>&1 || true)
    AVG=$(echo "$OUT" | grep -E "^avg:" | awk '{print $2}' || echo "?")
    P99=$(echo "$OUT" | grep -E "^p99:" | awk '{print $2}' || echo "?")
    OVER=$(echo "$OUT" | grep -E "^over:" | awk '{print $2}' || echo "?")
    printf "  %-30s avg=%-10s p99=%-10s over-budget=%s\n" "$g" "$AVG" "$P99" "$OVER"
  fi
done
echo

# --- Summary ---
echo "=== SUMMARY ==="
echo "$SCAN_LINE"
if [ "$DETM_FAIL" = "0" ]; then
  echo "Determinism: all games deterministic ✓"
else
  echo "Determinism: $DETM_FAIL game(s) failed ✗"
fi
if [ "$FUZZ_CRASH" = "0" ]; then
  echo "Fuzz: no crashes ✓"
else
  echo "Fuzz: $FUZZ_CRASH game(s) had crashes ✗"
fi

if [ "$DETM_FAIL" -gt 0 ] || [ "$FUZZ_CRASH" -gt 0 ]; then
  exit 1
fi
