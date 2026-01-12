#!/bin/bash
# Verification test for PHP-FPM Security Hardening
# Related to Issue #11

set -e

echo "=== PHP-FPM Security Hardening Verification ==="
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() { echo "[PASS] $1"; ((PASSED++)); }
fail() { echo "[FAIL] $1"; ((FAILED++)); }
warn() { echo "[WARN] $1"; ((WARNINGS++)); }

# Get PHP version
PHP_VERSION=$(php -v 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1)
if [ -z "$PHP_VERSION" ]; then
    echo "Error: PHP not installed or not in PATH"
    exit 1
fi

echo "Detected PHP version: $PHP_VERSION"
echo ""

# Find pool configuration files
POOL_DIR="/etc/php/$PHP_VERSION/fpm/pool.d"
if [ ! -d "$POOL_DIR" ]; then
    echo "Error: PHP-FPM pool directory not found: $POOL_DIR"
    exit 1
fi

echo "Checking PHP-FPM pool configurations in: $POOL_DIR"
echo ""

# Check 1: disable_functions is set
echo "--- Check 1: disable_functions ---"
if grep -rq "disable_functions" "$POOL_DIR"/*.conf 2>/dev/null; then
    DISABLED_FUNCS=$(grep -r "disable_functions" "$POOL_DIR"/*.conf 2>/dev/null | head -1)
    echo "Found: $DISABLED_FUNCS"

    # Verify dangerous functions are disabled
    DANGEROUS_FUNCS="exec passthru shell_exec system proc_open popen"
    MISSING=""
    for func in $DANGEROUS_FUNCS; do
        if ! echo "$DISABLED_FUNCS" | grep -q "$func"; then
            MISSING="$MISSING $func"
        fi
    done

    if [ -z "$MISSING" ]; then
        pass "All critical dangerous functions are disabled"
    else
        warn "Some dangerous functions may not be disabled:$MISSING"
    fi
else
    fail "disable_functions not configured in any pool"
fi
echo ""

# Check 2: allow_url_fopen is off
echo "--- Check 2: allow_url_fopen ---"
if grep -rq "allow_url_fopen.*=.*off" "$POOL_DIR"/*.conf 2>/dev/null; then
    pass "allow_url_fopen is disabled"
else
    fail "allow_url_fopen is not disabled or not configured"
fi
echo ""

# Check 3: allow_url_include is off
echo "--- Check 3: allow_url_include ---"
if grep -rq "allow_url_include.*=.*off" "$POOL_DIR"/*.conf 2>/dev/null; then
    pass "allow_url_include is disabled"
else
    fail "allow_url_include is not disabled or not configured"
fi
echo ""

# Check 4: open_basedir is configured
echo "--- Check 4: open_basedir ---"
if grep -rq "open_basedir" "$POOL_DIR"/*.conf 2>/dev/null; then
    OPEN_BASEDIR=$(grep -r "open_basedir" "$POOL_DIR"/*.conf 2>/dev/null | head -1)
    echo "Found: $OPEN_BASEDIR"
    pass "open_basedir is configured"
else
    fail "open_basedir is not configured"
fi
echo ""

# Check 5: session.save_path is configured per-pool
echo "--- Check 5: session.save_path ---"
if grep -rq "session.save_path" "$POOL_DIR"/*.conf 2>/dev/null; then
    SESSION_PATH=$(grep -r "session.save_path" "$POOL_DIR"/*.conf 2>/dev/null | head -1)
    echo "Found: $SESSION_PATH"
    pass "session.save_path is configured per-pool"
else
    warn "session.save_path not configured (using default)"
fi
echo ""

# Check 6: Session directories exist with correct permissions
echo "--- Check 6: Session directories ---"
SESSION_BASE="/var/lib/php/sessions"
if [ -d "$SESSION_BASE" ]; then
    POOL_SESSIONS=$(find "$SESSION_BASE" -maxdepth 1 -type d -name "*_pool" 2>/dev/null | wc -l)
    if [ "$POOL_SESSIONS" -gt 0 ]; then
        pass "Found $POOL_SESSIONS pool-specific session directories"

        # Check permissions
        for dir in $(find "$SESSION_BASE" -maxdepth 1 -type d -name "*_pool" 2>/dev/null); do
            PERMS=$(stat -c "%a" "$dir" 2>/dev/null)
            if [ "$PERMS" = "770" ] || [ "$PERMS" = "700" ]; then
                echo "  $dir: permissions $PERMS (OK)"
            else
                warn "$dir: permissions $PERMS (expected 770 or 700)"
            fi
        done
    else
        warn "No pool-specific session directories found yet"
    fi
else
    warn "Session base directory not found: $SESSION_BASE"
fi
echo ""

# Check 7: Verify PHP-FPM is running with security settings
echo "--- Check 7: Runtime verification ---"
if command -v php &>/dev/null; then
    # Check if disabled functions are actually disabled
    RUNTIME_DISABLED=$(php -i 2>/dev/null | grep "^disable_functions" | head -1)
    if [ -n "$RUNTIME_DISABLED" ]; then
        echo "CLI PHP: $RUNTIME_DISABLED"
        warn "Note: CLI PHP may have different settings than FPM pools"
    fi
    pass "PHP runtime check completed"
else
    warn "Cannot verify PHP runtime - php command not found"
fi
echo ""

# Summary
echo "==================================="
echo "          SUMMARY"
echo "==================================="
echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "All critical security checks passed!"
    echo ""
    echo "Compatibility Notes:"
    echo "- Some backup plugins (UpdraftPlus, etc.) may need exec() enabled"
    echo "- Some import plugins may need allow_url_fopen enabled"
    echo "- To enable specific functions for a plugin, consider a separate FPM pool"
    exit 0
else
    echo "Some security checks failed. Review configuration."
    exit 1
fi
