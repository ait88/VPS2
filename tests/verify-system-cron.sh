#!/bin/bash
# tests/verify-system-cron.sh
# Verification script for WordPress system cron replacement (#6)
# Tests that WP-Cron is disabled and system cron is properly configured

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Verifying WordPress System Cron Configuration..."
echo "================================================"
echo

# Get WordPress root and domain from state or arguments
WP_ROOT="${1:-/var/www/html}"
DOMAIN="${2:-}"

echo "WordPress root: $WP_ROOT"
[ -n "$DOMAIN" ] && echo "Domain: $DOMAIN"
echo

# Check 1: Verify DISABLE_WP_CRON is set in wp-config.php
echo -n "1. Checking DISABLE_WP_CRON in wp-config.php... "
if [ ! -f "$WP_ROOT/wp-config.php" ]; then
    echo -e "${YELLOW}⚠${NC} wp-config.php not found at $WP_ROOT"
    echo "   This test requires an installed WordPress instance"
    exit 1
fi

if grep -q "define.*DISABLE_WP_CRON.*true" "$WP_ROOT/wp-config.php"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ DISABLE_WP_CRON not set to true${NC}"
    echo "   Expected: define( 'DISABLE_WP_CRON', true );"
    exit 1
fi

# Check 2: Find and verify cron file exists
echo -n "2. Checking for system cron file... "
CRON_FILES=($(find /etc/cron.d/ -name "wordpress-*" -type f 2>/dev/null || true))

if [ ${#CRON_FILES[@]} -eq 0 ]; then
    echo -e "${RED}✗ No WordPress cron files found${NC}"
    echo "   Expected: /etc/cron.d/wordpress-*"
    exit 1
elif [ ${#CRON_FILES[@]} -gt 1 ]; then
    echo -e "${YELLOW}⚠${NC} Multiple cron files found: ${CRON_FILES[*]}"
    CRON_FILE="${CRON_FILES[0]}"
    echo "   Using: $CRON_FILE"
else
    CRON_FILE="${CRON_FILES[0]}"
    echo -e "${GREEN}✓${NC} $CRON_FILE"
fi

# Check 3: Verify cron file has correct permissions
echo -n "3. Checking cron file permissions... "
PERMS=$(stat -c "%a" "$CRON_FILE")
if [ "$PERMS" = "644" ]; then
    echo -e "${GREEN}✓${NC} ($PERMS)"
else
    echo -e "${YELLOW}⚠${NC} Permissions are $PERMS (expected 644)"
fi

# Check 4: Verify cron file contains WP-CLI command
echo -n "4. Checking cron job command... "
if grep -q "wp cron event run --due-now" "$CRON_FILE"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ WP-CLI cron command not found${NC}"
    echo "   Expected: wp cron event run --due-now"
    exit 1
fi

# Check 5: Verify cron runs every minute
echo -n "5. Checking cron schedule... "
if grep -q "^\* \* \* \* \*" "$CRON_FILE"; then
    echo -e "${GREEN}✓${NC} (every minute)"
else
    echo -e "${YELLOW}⚠${NC} Non-standard schedule found"
fi

# Check 6: Verify WP-CLI is available
echo -n "6. Checking WP-CLI availability... "
if command -v wp &>/dev/null; then
    WP_VERSION=$(wp --version 2>/dev/null | awk '{print $2}')
    echo -e "${GREEN}✓${NC} (version $WP_VERSION)"
else
    echo -e "${YELLOW}⚠${NC} WP-CLI not found in PATH"
    echo "   Cron job may fail without WP-CLI installed"
fi

# Check 7: Extract and verify WordPress user from cron file
echo -n "7. Checking WordPress user in cron job... "
WP_USER=$(grep "^\* \* \* \* \*" "$CRON_FILE" | awk '{print $6}')
if [ -n "$WP_USER" ]; then
    if id "$WP_USER" &>/dev/null; then
        echo -e "${GREEN}✓${NC} ($WP_USER exists)"
    else
        echo -e "${RED}✗ User $WP_USER does not exist${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Could not extract user from cron file${NC}"
    exit 1
fi

# Check 8: Verify WordPress root path in cron file
echo -n "8. Checking WordPress path in cron job... "
CRON_PATH=$(grep "^\* \* \* \* \*" "$CRON_FILE" | grep -oP 'cd \K[^ ]+')
if [ -n "$CRON_PATH" ]; then
    if [ -d "$CRON_PATH" ]; then
        echo -e "${GREEN}✓${NC} ($CRON_PATH exists)"
    else
        echo -e "${YELLOW}⚠${NC} Path $CRON_PATH not found"
    fi
else
    echo -e "${RED}✗ Could not extract path from cron file${NC}"
    exit 1
fi

echo
echo -e "${GREEN}All checks passed!${NC}"
echo
echo "Configuration details:"
echo "  Cron file: $CRON_FILE"
echo "  WordPress user: $WP_USER"
echo "  WordPress path: $CRON_PATH"
echo "  Schedule: Every minute"
echo
echo "Cron file contents:"
echo "──────────────────────────────────────"
cat "$CRON_FILE"
echo "──────────────────────────────────────"
echo
echo "To test cron execution manually:"
echo "  sudo -u $WP_USER wp cron event run --due-now --path=$CRON_PATH"
echo
echo "To view cron events:"
echo "  sudo -u $WP_USER wp cron event list --path=$CRON_PATH"
echo
echo "Note: System cron replacement improves reliability for low-traffic sites"
echo "      where WordPress's built-in WP-Cron may not trigger regularly."
