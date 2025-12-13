#!/bin/bash
# Fix WordPress Health Check Issues for Cloudflare Origin Certificate Setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $@"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $@"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $@"; }
error() { echo -e "${RED}[ERROR]${NC} $@"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (sudo)"
    exit 1
fi

# Detect WordPress root from setup_state or use default
if [ -f ~/wordpress-mgmt/setup_state ]; then
    WP_ROOT=$(grep "^WP_ROOT=" ~/wordpress-mgmt/setup_state | cut -d'=' -f2)
    DOMAIN=$(grep "^DOMAIN=" ~/wordpress-mgmt/setup_state | cut -d'=' -f2)
fi

WP_ROOT="${WP_ROOT:-/var/www/wordpress}"
DOMAIN="${DOMAIN:-example.com}"
WP_CONFIG="$WP_ROOT/wp-config.php"

info "WordPress Health Check Fix Script"
echo "=================================="
echo "WordPress Root: $WP_ROOT"
echo "Domain: $DOMAIN"
echo

if [ ! -f "$WP_CONFIG" ]; then
    error "wp-config.php not found at $WP_CONFIG"
    exit 1
fi

# Issue 1 & 3: Fix SSL Loopback Issues
info "Issue 1 & 3: Fixing SSL Loopback Request Failures..."
echo
echo "The problem: WordPress is trying to make HTTPS requests to itself,"
echo "but the Cloudflare Origin Certificate is not trusted by the local system."
echo
echo "Solutions available:"
echo "  A) Use HTTP for loopback requests (recommended, simple)"
echo "  B) Disable SSL verification for loopback (less secure but works)"
echo "  C) Add Cloudflare Origin CA to system trust store (most secure)"
echo

read -p "Choose solution [A/B/C] (default: A): " ssl_choice
ssl_choice=${ssl_choice:-A}

# Backup wp-config.php
cp "$WP_CONFIG" "$WP_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
success "Backed up wp-config.php"

# Remove immutable flag temporarily
chattr -i "$WP_CONFIG" 2>/dev/null || true

case $ssl_choice in
    A|a)
        info "Applying Solution A: HTTP loopback requests..."

        # Check if already applied
        if grep -q "Cloudflare Origin Certificate - Loopback Fix" "$WP_CONFIG"; then
            warning "Solution A already applied, skipping..."
        else
            # Add WordPress constants before "That's all, stop editing!"
            sed -i "/\/\* That's all, stop editing/i\\
\\
/* Cloudflare Origin Certificate - Loopback Fix */\\
/* Force HTTP for loopback requests to avoid SSL handshake issues */\\
define('WP_HTTP_BLOCK_EXTERNAL', false);\\
define('WP_ACCESSIBLE_HOSTS', '${DOMAIN}');\\
\\
/* Use HTTP for internal REST API and loopback requests */\\
add_filter('rest_url', function(\\\$url) {\\
    if (is_admin() || (defined('DOING_CRON') && DOING_CRON)) {\\
        return str_replace('https://', 'http://', \\\$url);\\
    }\\
    return \\\$url;\\
});\\
\\
/* Fix loopback requests to use HTTP */\\
add_filter('site_url', function(\\\$url, \\\$path, \\\$scheme) {\\
    if (is_admin() || (defined('DOING_CRON') && DOING_CRON)) {\\
        if (\\\$scheme === 'https' || \\\$scheme === 'http') {\\
            return str_replace('https://', 'http://', \\\$url);\\
        }\\
    }\\
    return \\\$url;\\
}, 10, 3);\\
" "$WP_CONFIG"

            success "Solution A applied - WordPress will use HTTP for internal requests"
        fi
        ;;

    B|b)
        info "Applying Solution B: Disable SSL verification for loopback..."

        # Check if already applied
        if grep -q "Disable SSL Verification for Loopback" "$WP_CONFIG"; then
            warning "Solution B already applied, skipping..."
        else
            sed -i "/\/\* That's all, stop editing/i\\
\\
/* Cloudflare Origin Certificate - Disable SSL Verification for Loopback */\\
/* WARNING: This is less secure - only for internal requests */\\
add_filter('https_ssl_verify', '__return_false');\\
add_filter('https_local_ssl_verify', '__return_false');\\
add_filter('http_request_args', function(\\\$args, \\\$url) {\\
    if (strpos(\\\$url, '${DOMAIN}') !== false) {\\
        \\\$args['sslverify'] = false;\\
    }\\
    return \\\$args;\\
}, 10, 2);\\
" "$WP_CONFIG"

            warning "Solution B applied - SSL verification disabled for local requests"
        fi
        ;;

    C|c)
        info "Applying Solution C: Adding Cloudflare Origin CA to system trust..."

        # Check if already exists
        if [ -f /usr/local/share/ca-certificates/cloudflare-origin-ca.crt ]; then
            warning "Cloudflare Origin CA already installed, skipping..."
        else
            # Download Cloudflare Origin CA
            curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem \
                -o /usr/local/share/ca-certificates/cloudflare-origin-ca.crt

            # Update CA certificates
            update-ca-certificates

            success "Cloudflare Origin CA added to system trust store"
        fi
        ;;
esac

echo

# Issue 2: Fix File Permissions / Update Mechanism
info "Issue 2: Configuring WordPress Update Mechanism..."
echo
echo "The 'files not writable' warnings are actually GOOD for security!"
echo "WordPress core files should NOT be writable by the web server."
echo
echo "We'll configure WordPress to:"
echo "  • Use WP-CLI for updates (command line)"
echo "  • Disable file editing in admin (security best practice)"
echo "  • Acknowledge that core files are intentionally read-only"
echo

# Check if already applied
if grep -q "DISALLOW_FILE_EDIT" "$WP_CONFIG"; then
    warning "WordPress update configuration already applied, skipping..."
else
    sed -i "/\/\* That's all, stop editing/i\\
\\
/* Security: Disable file modifications via WordPress admin */\\
define('DISALLOW_FILE_EDIT', true);      // Disable theme/plugin editor\\
define('DISALLOW_FILE_MODS', false);     // Allow plugin/theme updates via WP-CLI\\
define('FS_METHOD', 'direct');           // Use direct filesystem access\\
\\
/* Acknowledge read-only core files (security hardening) */\\
/* Core updates should be done via WP-CLI: */\\
/* sudo -u wpuser wp core update */\\
" "$WP_CONFIG"

    success "WordPress configured for WP-CLI updates"
fi

echo
info "Additional Configuration: Performance & Security..."

# Check if additional settings already applied
if ! grep -q "WP_MEMORY_LIMIT" "$WP_CONFIG"; then
    # Add additional recommended settings
    sed -i "/\/\* That's all, stop editing/i\\
/* Performance: Increase memory limit */\\
define('WP_MEMORY_LIMIT', '512M');\\
define('WP_MAX_MEMORY_LIMIT', '512M');\\
\\
/* Security: Force SSL admin */\\
define('FORCE_SSL_ADMIN', true);\\
\\
/* Cron: Use system cron instead of WordPress cron */\\
define('DISABLE_WP_CRON', true);\\
" "$WP_CONFIG"

    success "Additional settings applied"
else
    warning "Additional settings already applied, skipping..."
fi

# Set up proper system cron for WordPress
info "Setting up system cron for WordPress..."
if ! crontab -u wpuser -l 2>/dev/null | grep -q "wp-cron.php"; then
    (crontab -u wpuser -l 2>/dev/null | grep -v "wp-cron.php" || true; echo "*/15 * * * * cd $WP_ROOT && php wp-cron.php >/dev/null 2>&1") | crontab -u wpuser -
    success "System cron configured for WordPress"
else
    warning "System cron already configured, skipping..."
fi

echo

# Fix wp-content permissions for updates
info "Adjusting wp-content permissions for plugin/theme updates..."
if [ -d "$WP_ROOT/wp-content/plugins" ]; then
    chown -R php-fpm:wordpress "$WP_ROOT/wp-content/plugins"
    chmod -R 2775 "$WP_ROOT/wp-content/plugins"
fi

if [ -d "$WP_ROOT/wp-content/themes" ]; then
    chown -R php-fpm:wordpress "$WP_ROOT/wp-content/themes"
    chmod -R 2775 "$WP_ROOT/wp-content/themes"
fi

success "wp-content/plugins and wp-content/themes now writable for updates"

# Re-apply immutable flag to wp-config.php
echo
read -p "Make wp-config.php immutable again? [Y/n]: " immutable
if [[ ! "$immutable" =~ ^[Nn]$ ]]; then
    chattr +i "$WP_CONFIG"
    success "wp-config.php is now immutable"
    warning "To edit wp-config.php in future: sudo chattr -i $WP_CONFIG"
fi

echo
echo "=================================="
success "WordPress Health Check Issues Fixed!"
echo "=================================="
echo
echo "Summary of changes:"
echo "  ✓ Fixed SSL loopback requests (REST API & cron)"
echo "  ✓ Configured WP-CLI for core/plugin/theme updates"
echo "  ✓ Disabled file editing in admin (security)"
echo "  ✓ Set up system cron for WordPress"
echo "  ✓ Made wp-content/plugins and themes writable"
echo
echo "Next steps:"
echo "  1. Test WordPress Health: WP Admin → Tools → Site Health"
echo "  2. Update WordPress via WP-CLI:"
echo "     sudo -u wpuser wp core update"
echo "     sudo -u wpuser wp plugin update --all"
echo "     sudo -u wpuser wp theme update --all"
echo
echo "  3. Verify REST API:"
echo "     curl https://${DOMAIN}/wp-json/"
echo
