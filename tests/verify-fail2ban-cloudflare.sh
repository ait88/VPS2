#!/bin/bash
# tests/verify-fail2ban-cloudflare.sh
# Verification script for Fail2Ban Cloudflare real IP configuration (#10)
# Tests that Fail2Ban is configured correctly to ban real IPs, not Cloudflare IPs

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Verifying Fail2Ban Cloudflare Configuration..."
echo "==============================================="
echo

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && DOMAIN=$(ls /var/log/nginx/*_access.log 2>/dev/null | head -1 | sed 's|.*/||;s|_access.log||' || echo "")

echo "Domain: ${DOMAIN:-not detected}"
echo

# Check 1: Verify Fail2Ban is installed and running
echo -n "1. Checking Fail2Ban service... "
if ! command -v fail2ban-client &>/dev/null; then
    echo -e "${RED}✗ Fail2Ban not installed${NC}"
    exit 1
fi

if systemctl is-active --quiet fail2ban; then
    echo -e "${GREEN}✓${NC} (running)"
else
    echo -e "${RED}✗ Fail2Ban is not running${NC}"
    exit 1
fi

# Check 2: Verify Cloudflare real IP config exists (if Cloudflare mode)
echo -n "2. Checking Cloudflare real IP config... "
if [ -f "/etc/nginx/conf.d/cloudflare-real-ip.conf" ]; then
    echo -e "${GREEN}✓${NC} (found)"
else
    echo -e "${YELLOW}⚠${NC} Not found - may not be using Cloudflare"
fi

# Check 3: Verify real_ip_header is configured
echo -n "3. Checking CF-Connecting-IP header... "
if [ -f "/etc/nginx/conf.d/cloudflare-real-ip.conf" ]; then
    if grep -q "real_ip_header CF-Connecting-IP" /etc/nginx/conf.d/cloudflare-real-ip.conf; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ real_ip_header not configured${NC}"
        echo "   Fail2Ban will see Cloudflare IPs, not real visitor IPs!"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipped (no Cloudflare config)"
fi

# Check 4: Verify WordPress filter exists
echo -n "4. Checking WordPress filter... "
if [ -f "/etc/fail2ban/filter.d/wordpress.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ WordPress filter not found${NC}"
    exit 1
fi

# Check 5: Verify filter has correct regex
echo -n "5. Checking filter regex patterns... "
if grep -q "wp-login" /etc/fail2ban/filter.d/wordpress.conf && \
   grep -q "xmlrpc" /etc/fail2ban/filter.d/wordpress.conf; then
    echo -e "${GREEN}✓${NC} (wp-login + xmlrpc)"
else
    echo -e "${YELLOW}⚠${NC} Missing some patterns"
fi

# Check 6: Verify WordPress jail exists
echo -n "6. Checking WordPress jail... "
if [ -f "/etc/fail2ban/jail.d/wordpress.conf" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ WordPress jail not found${NC}"
    exit 1
fi

# Check 7: Verify jail is enabled
echo -n "7. Checking jail is enabled... "
JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//')
if echo "$JAILS" | grep -q "wordpress"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} WordPress jails may not be active"
fi

# Check 8: Check log path exists
echo -n "8. Checking log file path... "
if [ -n "$DOMAIN" ] && [ -f "/var/log/nginx/${DOMAIN}_access.log" ]; then
    echo -e "${GREEN}✓${NC} (/var/log/nginx/${DOMAIN}_access.log)"
else
    echo -e "${YELLOW}⚠${NC} Log file not found"
fi

# Check 9: Verify logs contain real IPs (not Cloudflare IPs)
echo -n "9. Checking log IPs (should be real, not Cloudflare)... "
if [ -n "$DOMAIN" ] && [ -f "/var/log/nginx/${DOMAIN}_access.log" ]; then
    # Count IPs that look like Cloudflare (172.64.x.x, 162.158.x.x, etc.)
    CF_IPS=$(tail -100 "/var/log/nginx/${DOMAIN}_access.log" 2>/dev/null | \
             grep -oP '^\d+\.\d+\.\d+\.\d+' | \
             grep -cE '^(172\.6[4-9]|172\.[7-9]|162\.158|141\.101|108\.162|104\.(16|24)|103\.(21|22|31)|131\.0\.72|188\.114|190\.93|197\.234|198\.41)' || true)

    TOTAL_IPS=$(tail -100 "/var/log/nginx/${DOMAIN}_access.log" 2>/dev/null | \
                grep -cP '^\d+\.\d+\.\d+\.\d+' || true)

    if [ "$TOTAL_IPS" -gt 0 ]; then
        if [ "$CF_IPS" -eq 0 ]; then
            echo -e "${GREEN}✓${NC} (no Cloudflare IPs in recent logs)"
        elif [ "$CF_IPS" -lt "$((TOTAL_IPS / 2))" ]; then
            echo -e "${YELLOW}⚠${NC} Some Cloudflare IPs found ($CF_IPS/$TOTAL_IPS)"
        else
            echo -e "${RED}✗ Many Cloudflare IPs found ($CF_IPS/$TOTAL_IPS)${NC}"
            echo "   Real IP extraction may not be working!"
        fi
    else
        echo -e "${YELLOW}⚠${NC} No recent log entries to check"
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipped (no logs)"
fi

echo
echo -e "${GREEN}Verification complete!${NC}"
echo
echo "Fail2Ban jail status:"
echo "─────────────────────────────────────"
sudo fail2ban-client status 2>/dev/null | head -10
echo "─────────────────────────────────────"
echo
echo "WordPress jail details (if active):"
sudo fail2ban-client status wordpress-auth 2>/dev/null || echo "  (wordpress-auth jail not active)"
echo
echo "How it works:"
echo "  1. nginx extracts real IP from CF-Connecting-IP header"
echo "  2. Real IP is logged to access.log"
echo "  3. Fail2Ban reads access.log"
echo "  4. Fail2Ban bans the REAL attacker IP, not Cloudflare"
echo
echo "Testing (be careful!):"
echo "  # View banned IPs"
echo "  sudo fail2ban-client status wordpress-auth"
echo
echo "  # Check recent log entries"
echo "  tail -20 /var/log/nginx/${DOMAIN}_access.log"
echo
echo "  # Manually test ban (use test IP)"
echo "  # sudo fail2ban-client set wordpress-auth banip 192.0.2.1"
echo
echo "Warning: Never ban Cloudflare IPs! Check /etc/nginx/conf.d/cloudflare-real-ip.conf"
