#!/bin/bash
# tests/verify-cloudflare-only.sh
# Verification script for Cloudflare-only access restriction (#8)
# Tests that direct access is blocked and only Cloudflare IPs are allowed

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Verifying Cloudflare-Only Access Configuration..."
echo "================================================="
echo

# Check 1: Verify cloudflare-only.conf exists
echo -n "1. Checking if cloudflare-only.conf exists... "
if [ -f "/etc/nginx/conf.d/cloudflare-only.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ File not found${NC}"
    echo "   Expected: /etc/nginx/conf.d/cloudflare-only.conf"
    exit 1
fi

# Check 2: Verify geo block is present
echo -n "2. Checking geo block structure... "
if grep -q "geo \$realip_remote_addr \$cloudflare_ip" /etc/nginx/conf.d/cloudflare-only.conf; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Geo block not found${NC}"
    exit 1
fi

# Check 3: Verify default is 0 (block)
echo -n "3. Checking default is set to block... "
if grep -q "default 0;" /etc/nginx/conf.d/cloudflare-only.conf; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Default not set to 0${NC}"
    exit 1
fi

# Check 4: Verify Cloudflare IPv4 ranges are present
echo -n "4. Checking Cloudflare IPv4 ranges... "
ipv4_count=$(grep -cE "^\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+ 1;" /etc/nginx/conf.d/cloudflare-only.conf || true)
if [ "$ipv4_count" -gt 10 ]; then
    echo -e "${GREEN}✓${NC} ($ipv4_count ranges)"
else
    echo -e "${RED}✗ Insufficient IPv4 ranges (found $ipv4_count)${NC}"
    exit 1
fi

# Check 5: Verify Cloudflare IPv6 ranges are present
echo -n "5. Checking Cloudflare IPv6 ranges... "
ipv6_count=$(grep -cE "^\s+[0-9a-f:]+/[0-9]+ 1;" /etc/nginx/conf.d/cloudflare-only.conf || true)
if [ "$ipv6_count" -gt 5 ]; then
    echo -e "${GREEN}✓${NC} ($ipv6_count ranges)"
else
    echo -e "${YELLOW}⚠${NC} Few IPv6 ranges found ($ipv6_count)"
fi

# Check 6: Verify localhost is whitelisted
echo -n "6. Checking localhost whitelist... "
if grep -q "127.0.0.1 1;" /etc/nginx/conf.d/cloudflare-only.conf && \
   grep -q "::1 1;" /etc/nginx/conf.d/cloudflare-only.conf; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Localhost not whitelisted${NC}"
    echo "   WP-CLI and health checks may fail"
    exit 1
fi

# Check 7: Verify site config includes the check
echo -n "7. Checking site config includes cloudflare_ip check... "
SITE_CONFIGS=$(find /etc/nginx/sites-enabled/ -type f -o -type l 2>/dev/null || true)
CHECK_FOUND=0

for config in $SITE_CONFIGS; do
    if grep -q '\$cloudflare_ip = 0' "$config" 2>/dev/null; then
        CHECK_FOUND=1
        break
    fi
done

if [ $CHECK_FOUND -eq 1 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} Check not found in site configs"
    echo "   This may be expected if Cloudflare WAF is not enabled"
fi

# Check 8: Verify weekly update cron exists
echo -n "8. Checking auto-update cron job... "
if [ -f "/etc/cron.weekly/update-cloudflare-only" ] && [ -x "/etc/cron.weekly/update-cloudflare-only" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} Cron job not found or not executable"
fi

# Check 9: Verify nginx configuration is valid
echo -n "9. Testing nginx configuration... "
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
echo "Configuration details:"
echo "  Geo block: /etc/nginx/conf.d/cloudflare-only.conf"
echo "  IPv4 ranges: $ipv4_count"
echo "  IPv6 ranges: $ipv6_count"
echo "  Localhost: whitelisted"
echo "  Auto-update: Weekly via /etc/cron.weekly/update-cloudflare-only"
echo
echo "How it works:"
echo "  - \$cloudflare_ip = 1 for Cloudflare IPs and localhost"
echo "  - \$cloudflare_ip = 0 for all other IPs (blocked)"
echo "  - Site config: if (\$cloudflare_ip = 0) { return 403; }"
echo
echo "Testing (requires a deployed site with Cloudflare enabled):"
echo "──────────────────────────────────────────────────────────"
echo "# Direct server access (should return 403):"
echo "  curl -I http://\${SERVER_IP}/"
echo "  curl -I https://\${SERVER_IP}/ -k"
echo
echo "# Access via Cloudflare (should work):"
echo "  curl -I https://\${DOMAIN}/"
echo
echo "# Local loopback (should work - for WP-CLI, health checks):"
echo "  curl -I http://127.0.0.1/"
echo
echo "Note: This prevents attackers from bypassing Cloudflare's WAF/DDoS protection"
