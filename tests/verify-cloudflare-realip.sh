#!/bin/bash
# tests/verify-cloudflare-realip.sh
# Verification script for Cloudflare Real IP detection (#7)
# Tests that nginx is configured to extract real visitor IPs when behind Cloudflare

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Verifying Cloudflare Real IP Configuration..."
echo "=============================================="
echo

# Check 1: Cloudflare real IP config file exists
echo -n "1. Checking if cloudflare-real-ip.conf exists... "
if [ -f "/etc/nginx/conf.d/cloudflare-real-ip.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ File not found${NC}"
    echo "   Expected: /etc/nginx/conf.d/cloudflare-real-ip.conf"
    exit 1
fi

# Check 2: Verify CF-Connecting-IP header is configured
echo -n "2. Checking real_ip_header directive... "
if grep -q "real_ip_header CF-Connecting-IP" /etc/nginx/conf.d/cloudflare-real-ip.conf; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ CF-Connecting-IP header not found${NC}"
    exit 1
fi

# Check 3: Verify Cloudflare IP ranges are present
echo -n "3. Checking Cloudflare IP ranges... "
ipv4_count=$(grep -c "set_real_ip_from.*\." /etc/nginx/conf.d/cloudflare-real-ip.conf || true)
ipv6_count=$(grep -c "set_real_ip_from.*:" /etc/nginx/conf.d/cloudflare-real-ip.conf || true)

if [ "$ipv4_count" -gt 10 ] && [ "$ipv6_count" -gt 5 ]; then
    echo -e "${GREEN}✓${NC} (${ipv4_count} IPv4 + ${ipv6_count} IPv6 ranges)"
else
    echo -e "${RED}✗ Insufficient IP ranges${NC}"
    echo "   Found: ${ipv4_count} IPv4, ${ipv6_count} IPv6"
    exit 1
fi

# Check 4: Verify weekly update cron exists
echo -n "4. Checking auto-update cron job... "
if [ -f "/etc/cron.weekly/update-cloudflare-ips" ] && [ -x "/etc/cron.weekly/update-cloudflare-ips" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Cron job not found or not executable${NC}"
    exit 1
fi

# Check 5: Verify nginx configuration is valid
echo -n "5. Testing nginx configuration... "
if sudo nginx -t &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ nginx -t failed${NC}"
    sudo nginx -t
    exit 1
fi

echo
echo -e "${GREEN}All checks passed!${NC}"
echo
echo "Configuration details:"
echo "  Config file: /etc/nginx/conf.d/cloudflare-real-ip.conf"
echo "  IPv4 ranges: $ipv4_count"
echo "  IPv6 ranges: $ipv6_count"
echo "  Auto-update: Weekly via /etc/cron.weekly/update-cloudflare-ips"
echo
echo "To manually update Cloudflare IP ranges:"
echo "  sudo /etc/cron.weekly/update-cloudflare-ips"
echo
echo "To verify real IPs in logs (after deployment):"
echo "  tail -f /var/log/nginx/access.log"
echo "  (Should show actual visitor IPs, not Cloudflare IPs like 172.x.x.x)"
