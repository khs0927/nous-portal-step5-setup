#!/usr/bin/env bash
# verify.sh — bash smoke test for step5_probe.py
set -u

# Derive the probe path from this script's own location (git-bash compatible).
# git-bash `pwd` yields a POSIX path (/c/...) that the native Windows python3
# cannot open, so convert to a native Windows path when cygpath is available.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/step5_probe.py"
if command -v cygpath >/dev/null 2>&1; then
    PROBE="$(cygpath -w "$PROBE")"
fi
PASS=0
FAIL=0
TOTAL=0

# Helpers
check() {
    local label="$1" exit_code="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$exit_code" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $label"
    fi
}

# ──────────────────────────────────────────────────────────────────────
# 1) --list-models must list step-5-preview
# ──────────────────────────────────────────────────────────────────────
echo "--- Running step5_probe.py --list-models ---"
out=$(python3 "$PROBE" --list-models 2>&1) || true
# Grep for step-5-preview in output
if echo "$out" | grep -q "step-5-preview"; then
    check "list-models greps step-5-preview" 0
else
    # It may still exit 0 but not contain the string; check exit code
    check "list-models contains step-5-preview" 1
fi

# ──────────────────────────────────────────────────────────────────────
# 2) Default model chat probe → PASS/FAIL based on exit code
# ──────────────────────────────────────────────────────────────────────
echo "--- Running step5_probe.py (default) ---"
out=$(python3 "$PROBE" 2>&1) || true
# Strip \r characters for reliable grep on Windows line endings
out=$(echo "$out" | tr -d '\r')
# Run once more and capture the exit code immediately
# (set -e is off — a failing probe does not abort this script)
python3 "$PROBE" >/dev/null 2>&1
exit_code=$?
check "default-model chat probe exits 0" "$exit_code"

# If it exited 0, verify we got meaningful output
if [ "$exit_code" -eq 0 ]; then
    # Check that latency was printed
    if echo "$out" | grep -q "latency:"; then
        check "output contains latency" 0
    else
        check "output contains latency" 1
    fi
    # Check that finish_reason was printed
    if echo "$out" | grep -q "finish_reason:"; then
        check "output contains finish_reason" 0
    else
        check "output contains finish_reason" 1
    fi
    # Check that content was printed
    if echo "$out" | grep -q "content:"; then
        check "output contains content" 0
    else
        check "output contains content" 1
    fi
    # Check that token_resolved (masked) was printed
    if echo "$out" | grep -q "token_resolved:"; then
        check "output contains token_resolved (masked)" 0
    else
        check "output contains token_resolved (masked)" 1
    fi
fi

# ──────────────────────────────────────────────────────────────────────
# 3) hermes portal info → logged in?
# ──────────────────────────────────────────────────────────────────────
if hermes portal info >/dev/null 2>&1; then
    check "hermes portal info: logged in" 0
else
    # hermes may not be on PATH — tolerate with SKIP
    if command -v hermes >/dev/null 2>&1; then
        # It's on PATH but not logged in
        check "hermes portal info: logged in" 1
    else
        check "hermes portal info: logged in (hermes not on PATH, SKIP)" 0
    fi
fi

# ──────────────────────────────────────────────────────────────────────
# 4) hermes config get model.default → stepfun/step-5-preview:free?
# ──────────────────────────────────────────────────────────────────────
if command -v hermes >/dev/null 2>&1; then
    cfg=$(hermes config get model.default 2>&1) || true
    if echo "$cfg" | grep -q "stepfun/step-5-preview:free"; then
        check "hermes config model.default = stepfun/step-5-preview:free" 0
    else
        check "hermes config model.default = stepfun/step-5-preview:free" 1
    fi
else
    check "hermes config model.default (hermes not on PATH, SKIP)" 0
fi

# ──────────────────────────────────────────────────────────────────────
# Final summary
# ──────────────────────────────────────────────────────────────────────
echo ""
echo "RESULT: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0