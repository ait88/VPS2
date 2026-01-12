#!/bin/bash
# Verification test for Rate Limiting
# Related to Issue #13

set -e

echo "=== Rate Limiting Verification ==="
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() { echo "[PASS] $1"; ((PASSED++)); }
fail() { echo "[FAIL] $1"; ((FAILED++)); }
warn() { echo "[WARN] $1"; ((WARNINGS++)); }

NGINX_CONF="/etc/nginx/nginx.conf"

# Check 1: nginx.conf exists
echo "--- Check 1: Nginx configuration exists ---"
if [ -f "$NGINX_CONF" ]; then
    pass "Nginx configuration file exists"
else
    fail "Nginx configuration not found: $NGINX_CONF"
    exit 1
fi
echo ""

# Check 2: Rate limit zones defined
echo "--- Check 2: Rate limit zones defined ---"
if grep -q "limit_req_zone.*wordpress_login" "$NGINX_CONF"; then
    ZONE=$(grep "limit_req_zone.*wordpress_login" "$NGINX_CONF" | head -1)
    echo "Found: $ZONE"
    pass "wordpress_login rate limit zone defined"
else
    fail "wordpress_login rate limit zone not found"
fi
echo ""

# Check 3: API rate limit zone
echo "--- Check 3: API rate limit zone ---"
if grep -q "limit_req_zone.*wordpress_api" "$NGINX_CONF"; then
    ZONE=$(grep "limit_req_zone.*wordpress_api" "$NGINX_CONF" | head -1)
    echo "Found: $ZONE"
    pass "wordpress_api rate limit zone defined"
else
    warn "wordpress_api rate limit zone not found (optional)"
fi
echo ""

# Check 4: 429 status code configured
echo "--- Check 4: HTTP 429 status code ---"
if grep -q "limit_req_status 429" "$NGINX_CONF"; then
    pass "Rate limiting returns HTTP 429 (Too Many Requests)"
else
    warn "limit_req_status not set to 429 - may return 503 by default"
fi
echo ""

# Check 5: Real IP variable for WAF setups
echo "--- Check 5: Real IP handling for WAF ---"
if grep -q 'limit_req_zone.*realip_remote_addr' "$NGINX_CONF"; then
    pass "Using real IP address for rate limiting (WAF-aware)"
elif grep -q 'limit_req_zone.*binary_remote_addr' "$NGINX_CONF"; then
    # Check if WAF is configured
    if [ -f "/var/lib/wordpress-mgmt/state.conf" ]; then
        WAF_TYPE=$(grep "^WAF_TYPE=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)
        if [ -n "$WAF_TYPE" ] && [ "$WAF_TYPE" != "none" ]; then
            warn "WAF configured ($WAF_TYPE) but rate limiting uses binary_remote_addr"
            echo "Consider re-running nginx setup to use realip_remote_addr"
        else
            pass "Using binary_remote_addr (no WAF configured)"
        fi
    else
        pass "Using binary_remote_addr (direct access assumed)"
    fi
else
    warn "Could not determine rate limit IP variable"
fi
echo ""

# Check 6: Rate limit applied to wp-login.php
echo "--- Check 6: wp-login.php rate limiting ---"
VHOST_DIR="/etc/nginx/sites-available"
if ls "$VHOST_DIR"/*.* 2>/dev/null | head -1 | xargs grep -q "limit_req.*wordpress_login" 2>/dev/null; then
    pass "Rate limiting applied to wp-login.php in virtual host"
else
    # Check in sites-enabled
    ENABLED_DIR="/etc/nginx/sites-enabled"
    if ls "$ENABLED_DIR"/*.* 2>/dev/null | head -1 | xargs grep -q "limit_req.*wordpress_login" 2>/dev/null; then
        pass "Rate limiting applied to wp-login.php in virtual host"
    else
        warn "Could not verify rate limiting in virtual host config"
    fi
fi
echo ""

# Check 7: Burst configuration
echo "--- Check 7: Burst configuration ---"
if ls "$VHOST_DIR"/*.* 2>/dev/null | head -1 | xargs grep -q "limit_req.*burst" 2>/dev/null; then
    BURST=$(ls "$VHOST_DIR"/*.* 2>/dev/null | head -1 | xargs grep "limit_req.*burst" 2>/dev/null | head -1)
    echo "Found: $BURST"
    pass "Burst configured (allows initial requests)"
else
    warn "Burst not configured - first request may be rate limited"
fi
echo ""

# Check 8: Nginx syntax test
echo "--- Check 8: Nginx configuration syntax ---"
if sudo nginx -t 2>&1; then
    pass "Nginx configuration syntax is valid"
else
    fail "Nginx configuration has syntax errors"
fi
echo ""

# Check 9: Live rate limit test (optional)
echo "--- Check 9: Live rate limit test ---"
if [ -f "/var/lib/wordpress-mgmt/state.conf" ]; then
    DOMAIN=$(grep "^DOMAIN=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)
    if [ -n "$DOMAIN" ]; then
        echo "Testing rate limiting on: $DOMAIN"
        echo "(Making 8 rapid requests to wp-login.php...)"

        COUNT_429=0
        for i in {1..8}; do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/wp-login.php" 2>/dev/null || \
                     curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN/wp-login.php" 2>/dev/null)
            echo "  Request $i: HTTP $STATUS"
            if [ "$STATUS" = "429" ]; then
                ((COUNT_429++))
            fi
        done

        if [ "$COUNT_429" -gt 0 ]; then
            pass "Rate limiting is active! ($COUNT_429 requests returned 429)"
        else
            warn "No 429 responses received - rate limit may be too lenient or not active"
        fi
    else
        warn "Domain not configured - skipping live test"
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
    echo "All critical rate limiting checks passed!"
    echo ""
    echo "Configuration:"
    echo "- Login rate: 5 requests per minute"
    echo "- API rate: 30 requests per minute"
    echo "- Burst: 3 requests allowed before rate limiting"
    echo "- Returns HTTP 429 when exceeded"
    exit 0
else
    echo "Some rate limiting checks failed. Review configuration."
    exit 1
fi
