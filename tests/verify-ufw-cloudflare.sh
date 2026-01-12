#!/bin/bash
# tests/verify-ufw-cloudflare.sh
# Verification script for UFW Cloudflare-only configuration (#9)
# Tests that UFW firewall is configured to only allow Cloudflare IPs for HTTP/HTTPS

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Verifying UFW Cloudflare Configuration..."
echo "=========================================="
echo

# Check 1: Verify UFW is installed and active
echo -n "1. Checking UFW status... "
if ! command -v ufw &>/dev/null; then
    echo -e "${RED}✗ UFW not installed${NC}"
    exit 1
fi

UFW_STATUS=$(sudo ufw status | head -1)
if [[ "$UFW_STATUS" == *"active"* ]]; then
    echo -e "${GREEN}✓${NC} (active)"
else
    echo -e "${RED}✗ UFW is not active${NC}"
    echo "   Run: sudo ufw enable"
    exit 1
fi

# Check 2: Verify default policies
echo -n "2. Checking default policies... "
DEFAULT_INCOMING=$(sudo ufw status verbose | grep "Default:" | grep -oP 'incoming: \K\w+')
DEFAULT_OUTGOING=$(sudo ufw status verbose | grep "Default:" | grep -oP 'outgoing: \K\w+')

if [ "$DEFAULT_INCOMING" = "deny" ] && [ "$DEFAULT_OUTGOING" = "allow" ]; then
    echo -e "${GREEN}✓${NC} (deny incoming, allow outgoing)"
else
    echo -e "${YELLOW}⚠${NC} Non-standard defaults (incoming: $DEFAULT_INCOMING, outgoing: $DEFAULT_OUTGOING)"
fi

# Check 3: Verify SSH rule exists (should NEVER be removed)
echo -n "3. Checking SSH rule preserved... "
if sudo ufw status | grep -qE "22/(tcp|udp)|22\s+ALLOW"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ SSH rule not found - THIS IS CRITICAL${NC}"
    echo "   You may lose SSH access! Add: sudo ufw allow 22/tcp"
    exit 1
fi

# Check 4: Verify NO general 80/443 rules (should be Cloudflare-only)
echo -n "4. Checking no general HTTP/HTTPS rules... "
GENERAL_80=$(sudo ufw status | grep -E "^80\s+ALLOW\s+Anywhere" | grep -v "Cloudflare" | wc -l)
GENERAL_443=$(sudo ufw status | grep -E "^443\s+ALLOW\s+Anywhere" | grep -v "Cloudflare" | wc -l)

if [ "$GENERAL_80" -eq 0 ] && [ "$GENERAL_443" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} (no general rules)"
else
    echo -e "${YELLOW}⚠${NC} Found general 80/443 rules (not Cloudflare-restricted)"
    echo "   This may be intentional if WAF is not configured"
fi

# Check 5: Verify Cloudflare IPv4 rules exist
echo -n "5. Checking Cloudflare IPv4 rules... "
CF_IPV4_COUNT=$(sudo ufw status | grep -c "Cloudflare.*IPv4" || true)

if [ "$CF_IPV4_COUNT" -gt 10 ]; then
    echo -e "${GREEN}✓${NC} ($CF_IPV4_COUNT rules)"
else
    echo -e "${YELLOW}⚠${NC} Few Cloudflare IPv4 rules found ($CF_IPV4_COUNT)"
    echo "   This may be normal if Cloudflare WAF is not configured"
fi

# Check 6: Verify Cloudflare IPv6 rules exist
echo -n "6. Checking Cloudflare IPv6 rules... "
CF_IPV6_COUNT=$(sudo ufw status | grep -c "Cloudflare.*IPv6" || true)

if [ "$CF_IPV6_COUNT" -gt 5 ]; then
    echo -e "${GREEN}✓${NC} ($CF_IPV6_COUNT rules)"
else
    echo -e "${YELLOW}⚠${NC} Few Cloudflare IPv6 rules found ($CF_IPV6_COUNT)"
fi

# Check 7: Verify localhost database access
echo -n "7. Checking localhost MariaDB rule... "
if sudo ufw status | grep -q "3306.*127.0.0.1"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} MariaDB localhost rule not found"
fi

# Check 8: Total Cloudflare rules count
echo -n "8. Checking total Cloudflare rules... "
TOTAL_CF=$(sudo ufw status | grep -c "Cloudflare" || true)

if [ "$TOTAL_CF" -gt 15 ]; then
    echo -e "${GREEN}✓${NC} ($TOTAL_CF total Cloudflare rules)"
else
    echo -e "${YELLOW}⚠${NC} Total Cloudflare rules: $TOTAL_CF"
fi

echo
echo -e "${GREEN}UFW verification complete!${NC}"
echo
echo "Current UFW rules summary:"
echo "─────────────────────────────────────────"
sudo ufw status numbered | head -30
echo "─────────────────────────────────────────"
echo
echo "Defense in depth layers for Cloudflare:"
echo "  Layer 1: UFW firewall (this) - blocks at network level"
echo "  Layer 2: nginx geo block (#8) - blocks at application level"
echo "  Layer 3: Cloudflare WAF - blocks at edge"
echo
echo "Testing (requires external machine):"
echo "  # From non-Cloudflare IP (should fail/timeout):"
echo "  curl -I http://\${SERVER_IP}/ --connect-timeout 5"
echo
echo "  # Via Cloudflare (should work):"
echo "  curl -I https://\${DOMAIN}/"
echo
echo "Note: UFW rules prevent traffic from even reaching nginx,"
echo "      providing defense in depth if nginx is misconfigured."
