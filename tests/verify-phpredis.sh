#!/bin/bash
# Verification test for PhpRedis Installation
# Related to Issue #14

set -e

echo "=== PhpRedis Installation Verification ==="
echo ""

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() { echo "[PASS] $1"; ((PASSED++)); }
fail() { echo "[FAIL] $1"; ((FAILED++)); }
warn() { echo "[WARN] $1"; ((WARNINGS++)); }

# Check 1: PHP installed
echo "--- Check 1: PHP installation ---"
if command -v php &>/dev/null; then
    PHP_VERSION=$(php -v | head -1 | grep -oP '\d+\.\d+' | head -1)
    echo "PHP version: $PHP_VERSION"
    pass "PHP is installed"
else
    fail "PHP is not installed"
    exit 1
fi
echo ""

# Check 2: PhpRedis extension installed
echo "--- Check 2: PhpRedis extension ---"
if php -m | grep -qi "^redis$"; then
    REDIS_EXT_VERSION=$(php -r "echo phpversion('redis');" 2>/dev/null)
    echo "PhpRedis version: $REDIS_EXT_VERSION"
    pass "PhpRedis extension is loaded"
else
    fail "PhpRedis extension is NOT loaded"
    echo ""
    echo "To install PhpRedis:"
    echo "  sudo apt install php${PHP_VERSION}-redis"
    echo "  sudo systemctl restart php${PHP_VERSION}-fpm"
fi
echo ""

# Check 3: Redis server installed
echo "--- Check 3: Redis server ---"
if command -v redis-server &>/dev/null; then
    REDIS_VERSION=$(redis-server --version | grep -oP 'v=\K[0-9.]+')
    echo "Redis server version: $REDIS_VERSION"
    pass "Redis server is installed"
else
    fail "Redis server is not installed"
fi
echo ""

# Check 4: Redis service running
echo "--- Check 4: Redis service status ---"
if systemctl is-active --quiet redis-server 2>/dev/null; then
    pass "Redis service is running"
elif systemctl is-active --quiet redis 2>/dev/null; then
    pass "Redis service is running (as 'redis')"
else
    fail "Redis service is not running"
    echo "Start with: sudo systemctl start redis-server"
fi
echo ""

# Check 5: Redis connectivity
echo "--- Check 5: Redis connectivity ---"
if command -v redis-cli &>/dev/null; then
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        pass "Redis server responds to PING"
    else
        warn "Redis server did not respond to PING (may require authentication)"
    fi
else
    warn "redis-cli not found - cannot test connectivity"
fi
echo ""

# Check 6: PHP-FPM has redis module
echo "--- Check 6: PHP-FPM redis module ---"
if [ -d "/etc/php/$PHP_VERSION/mods-available" ]; then
    if [ -f "/etc/php/$PHP_VERSION/mods-available/redis.ini" ]; then
        pass "Redis PHP module configuration exists"
    else
        warn "Redis PHP module config not found in mods-available"
    fi
else
    warn "PHP mods-available directory not found"
fi
echo ""

# Check 7: WordPress Redis integration (if installed)
echo "--- Check 7: WordPress Redis integration ---"
if [ -f "/var/lib/wordpress-mgmt/state.conf" ]; then
    WP_ROOT=$(grep "^WP_ROOT=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)
    WP_USER=$(grep "^WP_USER=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)
    ENABLE_REDIS=$(grep "^ENABLE_REDIS=" /var/lib/wordpress-mgmt/state.conf 2>/dev/null | cut -d= -f2)

    if [ "$ENABLE_REDIS" = "true" ] && [ -n "$WP_ROOT" ] && [ -n "$WP_USER" ]; then
        if [ -f "$WP_ROOT/wp-content/object-cache.php" ]; then
            pass "WordPress object-cache.php exists"

            # Check Redis Object Cache plugin status
            if command -v wp &>/dev/null; then
                echo "Checking WordPress Redis status..."
                REDIS_STATUS=$(sudo -u "$WP_USER" wp redis status --path="$WP_ROOT" 2>/dev/null || echo "error")

                if echo "$REDIS_STATUS" | grep -qi "PhpRedis"; then
                    pass "Redis Object Cache is using PhpRedis (optimal)"
                elif echo "$REDIS_STATUS" | grep -qi "Predis"; then
                    warn "Redis Object Cache is using Predis (slower than PhpRedis)"
                    echo "Install php-redis package for better performance"
                elif echo "$REDIS_STATUS" | grep -qi "Connected"; then
                    pass "Redis Object Cache is connected"
                else
                    warn "Could not determine Redis Object Cache client"
                fi
            else
                warn "WP-CLI not found - cannot check Redis Object Cache status"
            fi
        else
            warn "object-cache.php not found - Redis Object Cache plugin may not be activated"
        fi
    else
        warn "Redis not enabled in WordPress configuration"
    fi
else
    warn "WordPress state file not found - skipping WordPress check"
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
    if php -m | grep -qi "^redis$"; then
        echo "PhpRedis is properly installed and configured!"
        echo ""
        echo "Benefits over Predis:"
        echo "- 2-5x faster Redis operations"
        echo "- Lower memory usage"
        echo "- Native C extension vs pure PHP"
    else
        echo "Redis server is running, but PhpRedis extension is missing."
        echo "Install it for optimal WordPress object caching performance."
    fi
    exit 0
else
    echo "Some checks failed. Review the output above."
    exit 1
fi
