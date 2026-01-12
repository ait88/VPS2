#!/bin/bash
# tests/verify-nginx-security-blocks.sh
# Verification script for nginx security blocks (#15)
# Tests that xmlrpc.php, uploads PHP files, and other attack vectors are blocked

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Verifying Nginx Security Block Configuration..."
echo "==============================================="
echo

DOMAIN="${1:-localhost}"
echo "Testing domain: $DOMAIN"
echo

# Check 1: Verify wordpress-security.conf exists
echo -n "1. Checking wordpress-security.conf exists... "
if [ -f "/etc/nginx/snippets/wordpress-security.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ File not found${NC}"
    echo "   Expected: /etc/nginx/snippets/wordpress-security.conf"
    exit 1
fi

# Check 2: Verify xmlrpc.php block
echo -n "2. Checking xmlrpc.php block... "
if grep -q "location = /xmlrpc.php" /etc/nginx/snippets/wordpress-security.conf && \
   grep -A 3 "location = /xmlrpc.php" /etc/nginx/snippets/wordpress-security.conf | grep -q "deny all"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ xmlrpc.php block not found or incomplete${NC}"
    exit 1
fi

# Check 3: Verify xmlrpc.php has access_log off
echo -n "3. Checking xmlrpc.php has logging disabled... "
if grep -A 3 "location = /xmlrpc.php" /etc/nginx/snippets/wordpress-security.conf | grep -q "access_log off"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} access_log off not found (minor - still functional)"
fi

# Check 4: Verify uploads PHP block
echo -n "4. Checking uploads PHP execution block... "
if grep -q "uploads.*\.php" /etc/nginx/snippets/wordpress-security.conf && \
   grep -A 3 "uploads.*\.php" /etc/nginx/snippets/wordpress-security.conf | grep -q "deny all"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Uploads PHP block not found or incomplete${NC}"
    exit 1
fi

# Check 5: Verify uploads PHP has access_log off
echo -n "5. Checking uploads PHP has logging disabled... "
if grep -A 3 "uploads.*\.php" /etc/nginx/snippets/wordpress-security.conf | grep -q "access_log off"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} access_log off not found (minor - still functional)"
fi

# Check 6: Verify wp-config.php block
echo -n "6. Checking wp-config.php block... "
if grep -q "wp-config" /etc/nginx/snippets/wordpress-security.conf && \
   grep -A 2 "wp-config" /etc/nginx/snippets/wordpress-security.conf | grep -q "deny all"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ wp-config.php block not found${NC}"
    exit 1
fi

# Check 7: Verify debug.log block
echo -n "7. Checking debug.log block... "
if grep -q "debug.log" /etc/nginx/snippets/wordpress-security.conf && \
   grep -A 2 "debug.log" /etc/nginx/snippets/wordpress-security.conf | grep -q "deny all"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} debug.log block not found (minor)"
fi

# Check 8: Verify dotfile block
echo -n "8. Checking dotfile block... "
if grep -q "location ~ /\\\." /etc/nginx/snippets/wordpress-security.conf && \
   grep -A 3 "location ~ /\\\." /etc/nginx/snippets/wordpress-security.conf | grep -q "deny all"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} Dotfile block not found in wordpress-security.conf (may be in vhost)"
fi

# Check 9: Verify author scan block
echo -n "9. Checking author scan block... "
if grep -q "^/author/" /etc/nginx/snippets/wordpress-security.conf; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} Author scan block not found (minor)"
fi

# Check 10: Verify snippet is included in site config
echo -n "10. Checking snippet included in site config... "
SITE_CONFIGS=($(find /etc/nginx/sites-enabled/ -type f -o -type l 2>/dev/null))
if [ ${#SITE_CONFIGS[@]} -gt 0 ]; then
    INCLUDES_FOUND=0
    for config in "${SITE_CONFIGS[@]}"; do
        if grep -q "wordpress-security.conf" "$config"; then
            INCLUDES_FOUND=1
            break
        fi
    done

    if [ $INCLUDES_FOUND -eq 1 ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ wordpress-security.conf not included in any site config${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} No enabled site configs found"
fi

# Check 11: Test nginx configuration validity
echo -n "11. Testing nginx configuration... "
if sudo nginx -t &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ nginx -t failed${NC}"
    sudo nginx -t
    exit 1
fi

echo
echo -e "${GREEN}All critical checks passed!${NC}"
echo
echo "Configuration summary:"
echo "  Security snippet: /etc/nginx/snippets/wordpress-security.conf"
echo "  Blocks configured:"
echo "    • XML-RPC (xmlrpc.php)"
echo "    • PHP execution in uploads directory"
echo "    • Direct wp-config.php access"
echo "    • Debug.log exposure"
echo "    • Dotfile access"
echo "    • Author enumeration scans"
echo
echo "Live testing (requires running WordPress site):"
echo "──────────────────────────────────────────────"
echo "Test blocked paths (should all return 403):"
echo "  curl -I https://$DOMAIN/xmlrpc.php"
echo "  curl -I https://$DOMAIN/wp-content/uploads/test.php"
echo "  curl -I https://$DOMAIN/wp-config.php"
echo "  curl -I https://$DOMAIN/.htaccess"
echo "  curl -I https://$DOMAIN/wp-content/debug.log"
echo
echo "Test normal operation (should work):"
echo "  curl -I https://$DOMAIN/"
echo "  curl -I https://$DOMAIN/wp-admin/"
echo
echo "Note: access_log off reduces log noise from bot attacks"
