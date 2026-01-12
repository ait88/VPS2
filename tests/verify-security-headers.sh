#!/bin/bash
# Verification test for Security Headers
# Related to Issue #12

set -e

echo "=== Security Headers Verification ==="
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() { echo "[PASS] $1"; ((PASSED++)); }
fail() { echo "[FAIL] $1"; ((FAILED++)); }
warn() { echo "[WARN] $1"; ((WARNINGS++)); }

# Check if security-headers.conf exists
SECURITY_HEADERS="/etc/nginx/snippets/security-headers.conf"

echo "--- Check 1: Security headers file exists ---"
if [ -f "$SECURITY_HEADERS" ]; then
    pass "Security headers file exists: $SECURITY_HEADERS"
else
    fail "Security headers file not found: $SECURITY_HEADERS"
    echo "Run the WordPress setup to create this file."
    exit 1
fi
echo ""

# Check 2: X-Frame-Options
echo "--- Check 2: X-Frame-Options ---"
if grep -q "X-Frame-Options" "$SECURITY_HEADERS"; then
    VALUE=$(grep "X-Frame-Options" "$SECURITY_HEADERS" | head -1)
    echo "Found: $VALUE"
    pass "X-Frame-Options header configured"
else
    fail "X-Frame-Options header not found"
fi
echo ""

# Check 3: X-Content-Type-Options
echo "--- Check 3: X-Content-Type-Options ---"
if grep -q "X-Content-Type-Options.*nosniff" "$SECURITY_HEADERS"; then
    pass "X-Content-Type-Options set to nosniff"
else
    fail "X-Content-Type-Options not configured correctly"
fi
echo ""

# Check 4: X-XSS-Protection
echo "--- Check 4: X-XSS-Protection ---"
if grep -q "X-XSS-Protection" "$SECURITY_HEADERS"; then
    pass "X-XSS-Protection header configured"
else
    warn "X-XSS-Protection not found (may be deprecated in modern browsers)"
fi
echo ""

# Check 5: Referrer-Policy
echo "--- Check 5: Referrer-Policy ---"
if grep -q "Referrer-Policy" "$SECURITY_HEADERS"; then
    VALUE=$(grep "Referrer-Policy" "$SECURITY_HEADERS" | head -1)
    echo "Found: $VALUE"
    pass "Referrer-Policy header configured"
else
    fail "Referrer-Policy header not found"
fi
echo ""

# Check 6: Permissions-Policy
echo "--- Check 6: Permissions-Policy ---"
if grep -q "Permissions-Policy" "$SECURITY_HEADERS"; then
    VALUE=$(grep "Permissions-Policy" "$SECURITY_HEADERS" | head -1)
    echo "Found: $VALUE"
    pass "Permissions-Policy header configured"
else
    warn "Permissions-Policy header not found"
fi
echo ""

# Check 7: Content-Security-Policy
echo "--- Check 7: Content-Security-Policy ---"
if grep -q "Content-Security-Policy" "$SECURITY_HEADERS"; then
    VALUE=$(grep "Content-Security-Policy" "$SECURITY_HEADERS" | head -1)
    echo "Found: $VALUE"
    pass "Content-Security-Policy header configured"
    warn "CSP may need adjustment for your specific WordPress plugins"
else
    fail "Content-Security-Policy header not found"
fi
echo ""

# Check 8: HSTS (Strict-Transport-Security)
echo "--- Check 8: HSTS (Strict-Transport-Security) ---"
if grep -q "^add_header Strict-Transport-Security" "$SECURITY_HEADERS"; then
    VALUE=$(grep "Strict-Transport-Security" "$SECURITY_HEADERS" | head -1)
    echo "Found: $VALUE"
    pass "HSTS is enabled"

    # Verify max-age
    if echo "$VALUE" | grep -q "max-age=31536000"; then
        pass "HSTS max-age is 1 year (recommended)"
    else
        warn "HSTS max-age may not be optimal"
    fi
elif grep -q "# add_header Strict-Transport-Security" "$SECURITY_HEADERS"; then
    warn "HSTS is present but commented out"
    echo "HSTS will be enabled after SSL is configured."
    echo "If using Cloudflare WAF, HSTS is handled at the edge."
else
    warn "HSTS header not found"
fi
echo ""

# Check 9: Security headers included in nginx vhost
echo "--- Check 9: Security headers included in vhost ---"
if ls /etc/nginx/sites-available/*.* 2>/dev/null | head -1 | xargs grep -q "security-headers.conf" 2>/dev/null; then
    pass "Security headers included in virtual host"
else
    warn "Could not verify security headers inclusion in vhost"
fi
echo ""

# Check 10: Live header test (if domain configured)
echo "--- Check 10: Live header test ---"
if [ -f "/var/lib/wordpress-mgmt/state.conf" ]; then
    DOMAIN=$(grep "^DOMAIN=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$DOMAIN" ]; then
        echo "Testing headers for: $DOMAIN"

        # Try HTTPS first, then HTTP
        HEADERS=$(curl -sI "https://$DOMAIN" 2>/dev/null || curl -sI "http://$DOMAIN" 2>/dev/null)

        if [ -n "$HEADERS" ]; then
            echo ""
            echo "Received headers:"
            echo "$HEADERS" | grep -iE "x-frame|x-content|x-xss|referrer|permission|content-security|strict-transport" || true
            echo ""

            if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
                pass "X-Frame-Options present in live response"
            else
                warn "X-Frame-Options not found in live response"
            fi
        else
            warn "Could not connect to $DOMAIN to test headers"
        fi
    else
        warn "Domain not configured in state - skipping live test"
    fi
else
    warn "State file not found - skipping live test"
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
    echo "All critical security header checks passed!"
    echo ""
    echo "Notes:"
    echo "- CSP may need adjustment for specific plugins (contact forms, analytics, etc.)"
    echo "- HSTS is enabled after SSL is configured (or handled by WAF)"
    echo "- Test in browser DevTools for any CSP violations"
    exit 0
else
    echo "Some security header checks failed. Review configuration."
    exit 1
fi
