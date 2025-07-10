#!/bin/bash
# setup-wordpress.sh - Modular WordPress Installation Manager
# Version: 3.0.0
# GitHub: https://github.com/ait88/VPS2

set -euo pipefail

# ===== CONFIGURATION =====
SCRIPT_VERSION="3.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/ait88/VPS2/main/setup-wordpress.sh"
BASE_URL="https://raw.githubusercontent.com/ait88/VPS2/main/wordpress-mgmt"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WP_MGMT_DIR="$SCRIPT_DIR/wordpress-mgmt"
LIB_DIR="$WP_MGMT_DIR/lib"
STATE_FILE="$WP_MGMT_DIR/setup_state"
LOG_FILE="$WP_MGMT_DIR/setup.log"

# Create directory structure
mkdir -p "$LIB_DIR"

# ===== LOGGING SYSTEM =====
# Clean console output with detailed file logging
log_to_file() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
}

# Console output functions (clean, no timestamps)
info() {
    echo -e "\033[0;34m[INFO]\033[0m $@"
    log_to_file "INFO" "$@"
}

success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $@"
    log_to_file "SUCCESS" "$@"
}

warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $@"
    log_to_file "WARNING" "$@"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $@"
    log_to_file "ERROR" "$@"
}

debug() {
    # Only show if DEBUG=1
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "\033[0;90m[DEBUG]\033[0m $@"
    fi
    log_to_file "DEBUG" "$@"
}

# ===== MODULE MANAGEMENT =====
download_module() {
    local module_name=$1
    local module_path="$LIB_DIR/$module_name"
    local module_url="$BASE_URL/lib/$module_name"
    
    debug "Downloading module: $module_name"
    
    if command -v curl &> /dev/null; then
        curl -fsSL "$module_url" -o "$module_path" 2>/dev/null || {
            error "Failed to download module: $module_name"
            return 1
        }
    else
        error "curl is required but not installed"
        return 1
    fi
    
    chmod +x "$module_path"
    debug "Module downloaded: $module_path"
}

load_module() {
    local module_name=$1
    local module_path="$LIB_DIR/$module_name"
    
    # Download if not exists or if update requested
    if [ ! -f "$module_path" ] || [ "${UPDATE_MODULES:-0}" = "1" ]; then
        download_module "$module_name" || return 1
    fi
    
    # Source the module
    source "$module_path" || {
        error "Failed to load module: $module_name"
        return 1
    }
    
    debug "Module loaded: $module_name"
}

# Required modules in execution order
MODULES=(
    "utils.sh"           # Common utilities
    "preflight.sh"       # System checks
    "packages.sh"        # Install dependencies  
    "config.sh"          # Interactive configuration
    "users.sh"           # User management
    "database.sh"        # MariaDB setup
    "nginx.sh"           # Web server configuration
    "wordpress.sh"       # WordPress installation
    "ssl.sh"             # SSL/TLS setup
    "security.sh"        # Security hardening
    "backup.sh"          # Backup system
)

# ===== STATE MANAGEMENT =====
save_state() {
    local key=$1
    local value=$2
    touch "$STATE_FILE"
    
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
    debug "State saved: ${key}=${value}"
}

load_state() {
    local key=$1
    local default=${2:-""}
    
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- || echo "$default"
    else
        echo "$default"
    fi
}

state_exists() {
    local key=$1
    [ -f "$STATE_FILE" ] && grep -q "^${key}=" "$STATE_FILE" 2>/dev/null
}

remove_state() {
    local key=$1
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${key}=/d" "$STATE_FILE"
        debug "State removed: ${key}"
    fi
}

# ===== SELF-UPDATE =====
check_update() {
    info "Checking for updates..."
    
    local temp_script="/tmp/setup-wordpress-new.sh"
    curl -fsSL "$SCRIPT_URL" -o "$temp_script" 2>/dev/null || {
        warning "Failed to check for updates"
        return 1
    }
    
    local latest_version=$(grep "^SCRIPT_VERSION=" "$temp_script" | head -1 | cut -d'"' -f2)
    
    if [ -n "$latest_version" ] && [ "$latest_version" != "$SCRIPT_VERSION" ]; then
        echo -e "\033[1;33mNew version available: $latest_version (current: $SCRIPT_VERSION)\033[0m"
        read -p "Update now? [y/N]: " update_confirm
        
        if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
            cp "$0" "$0.backup-$(date +%Y%m%d-%H%M%S)"
            mv "$temp_script" "$0"
            chmod +x "$0"
            success "Updated to version $latest_version"
            exec "$0" "$@"
        fi
    else
        success "Running latest version ($SCRIPT_VERSION)"
    fi
    
    rm -f "$temp_script"
}

# ===== INSTALLATION MODES =====
mode_fresh_install() {
    info "=== Fresh WordPress Installation ==="
    
    # Load and execute modules
    for module in "${MODULES[@]}"; do
        load_module "$module" || {
            error "Failed to load required module: $module"
            exit 1
        }
    done
    
    # Execute installation steps
    run_preflight_checks
    install_packages
    configure_interactive
    setup_users
    setup_database
    configure_nginx
    install_wordpress
    setup_ssl
    apply_security
    setup_backup_system
    
    success "WordPress installation completed successfully!"
    show_completion_summary
}

mode_import_site() {
    info "=== Import Existing WordPress Site ==="
    
    # Load required modules
    for module in utils.sh preflight.sh config.sh users.sh database.sh packages.sh nginx.sh ssl.sh security.sh backup.sh wordpress.sh; do
        load_module "$module"
    done
    
    # Run preflight checks to ensure dependencies are installed
    run_preflight_checks
    
    import_wordpress_site
}

mode_restore_backup() {
    info "=== Restore from Backup ==="
    
    for module in utils.sh preflight.sh config.sh users.sh database.sh packages.sh nginx.sh ssl.sh security.sh backup.sh wordpress.sh; do
        load_module "$module"
    done
    
    # Run preflight checks to ensure dependencies are installed
    run_preflight_checks
    
    restore_from_backup
}

# ===== NUKE ALL FUNCTION =====
nuke_all() {
    info "=== Remove WordPress - Complete System Reset ==="
    
    # Load required modules
    for module in utils.sh database.sh; do
        load_module "$module"
    done
    
    echo
    echo -e "\033[1;31m⚠️  DANGER ZONE ⚠️\033[0m"
    echo "This will COMPLETELY REMOVE:"
    echo "• All MariaDB databases and users"
    echo "• All WordPress files and directories"
    echo "• All system users (wp-user, php-user, backup-user, etc.)"
    echo "• All configuration files and SSL certificates"
    echo "• Complete setup_state (all saved configuration)"
    echo
    echo -e "\033[1;31mTHIS CANNOT BE UNDONE!\033[0m"
    echo
    echo "Type 'I know what I'm doing, Nuke it all!' to proceed:"
    read -p "> " nuke_confirm
    
    if [ "$nuke_confirm" = "I know what I'm doing, Nuke it all!" ]; then
        nuke_complete_system
    else
        echo "Confirmation failed. Aborting."
        return 1
    fi
}

nuke_complete_system() {
    info "🔥 NUKING complete WordPress system..."
    
    # Backup current configuration for reference
    local domain=$(load_state "DOMAIN")
    local admin_email=$(load_state "ADMIN_EMAIL")
    local wp_root=$(load_state "WP_ROOT")
    
    # Stop all services
    info "Stopping services..."
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl stop php8.2-fpm 2>/dev/null || true
    sudo systemctl stop redis-server 2>/dev/null || true
    sudo systemctl stop mariadb 2>/dev/null || true
    
    # Remove MariaDB completely
    info "Removing MariaDB..."
    sudo systemctl stop mariadb || true
    sudo systemctl disable mariadb || true
    sudo apt-get remove --purge -y mariadb-server mariadb-client mariadb-common mysql-common 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
    sudo rm -rf /var/lib/mysql
    sudo rm -rf /etc/mysql
    sudo rm -f /etc/init.d/mysql
    sudo rm -f /etc/logrotate.d/mysql-server
    
    # Remove WordPress files
    if [ -n "$wp_root" ] && [ -d "$wp_root" ]; then
        info "Removing WordPress files at $wp_root..."
        sudo rm -rf "$wp_root"
    fi
    
    # Remove common WordPress directories
    sudo rm -rf /var/www/wordpress 2>/dev/null || true
    sudo rm -rf /var/www/html/wordpress 2>/dev/null || true
    
    # Remove system users
    info "Removing system users..."
    for user in wp-user php-user wp-backup redis backup-user; do
        if id "$user" &>/dev/null; then
            info "Removing user: $user"
            sudo userdel -r "$user" 2>/dev/null || true
        fi
    done
    
    # Remove SSL certificates
    info "Removing SSL certificates..."
    if [ -n "$domain" ]; then
        sudo rm -rf "/etc/letsencrypt/live/$domain" 2>/dev/null || true
        sudo rm -rf "/etc/letsencrypt/archive/$domain" 2>/dev/null || true
        sudo rm -rf "/etc/letsencrypt/renewal/$domain.conf" 2>/dev/null || true
    fi
    
    # Remove Nginx configuration
    info "Removing Nginx configuration..."
    sudo rm -f /etc/nginx/sites-available/wordpress* 2>/dev/null || true
    sudo rm -f /etc/nginx/sites-enabled/wordpress* 2>/dev/null || true
    if [ -n "$domain" ]; then
        sudo rm -f "/etc/nginx/sites-available/$domain" 2>/dev/null || true
        sudo rm -f "/etc/nginx/sites-enabled/$domain" 2>/dev/null || true
    fi
    
    # Remove PHP-FPM pools
    info "Removing PHP-FPM pools..."
    sudo rm -f /etc/php/8.2/fpm/pool.d/wordpress.conf 2>/dev/null || true
    
    # Remove fail2ban jails
    info "Removing security configurations..."
    sudo rm -f /etc/fail2ban/jail.d/wordpress.conf 2>/dev/null || true
    
    # Remove backup directories
    info "Removing backup directories..."
    sudo rm -rf /home/*/backups 2>/dev/null || true
    sudo rm -rf /home/*/db-backups 2>/dev/null || true
    
    # Remove user credentials
    info "Removing user credentials..."
    rm -f "$HOME/.mysql_root"
    rm -f "$HOME/.my.cnf"
    
    # Remove setup state completely
    info "Removing all configuration state..."
    rm -f "$STATE_FILE"
    
    # Remove logs
    info "Removing logs..."
    rm -f "$LOG_FILE"
    
    # Restart remaining services
    info "Restarting services..."
    sudo systemctl restart nginx 2>/dev/null || true
    sudo systemctl restart fail2ban 2>/dev/null || true
    
    echo
    success "✓ Complete system nuke successful!"
    echo
    if [ -n "$domain" ]; then
        info "💡 Previous configuration reference:"
        info "   Domain: $domain"
        info "   Email: $admin_email"
        info "   WordPress Root: $wp_root"
        echo
    fi
    info "🚀 System is now clean and ready for fresh WordPress installation"
    info "🚀 Run this script again to begin fresh setup"
    echo
    
    exit 0
}

# ===== MAIN MENU =====
show_menu() {
    echo
    echo -e "\033[1;34m=== WordPress Setup Script v${SCRIPT_VERSION} ===\033[0m"
    echo
    echo "Installation Options:"
    echo "1) Fresh WordPress installation"
    echo "2) Import existing WordPress site"  
    echo "3) Restore from backup"
    echo "4) Update modules"
    echo
    echo "Management Menus:"
    echo "6) Utils Menu (Permissions, Domain Change, Nuke)"
    echo "7) Monitoring Menu"
    echo "8) Maintenance Menu"
    echo
    echo "9) Exit"
    echo
    read -p "Enter your choice [1-9]: " choice
    echo
    
    case $choice in
        1) mode_fresh_install ;;
        2) mode_import_site ;;
        3) mode_restore_backup ;;
        4) 
            UPDATE_MODULES=1
            info "Updating all modules..."
            for module in "${MODULES[@]}"; do
                download_module "$module"
            done
            success "All modules updated"
            show_menu
            ;;
        6) show_utils_menu ;;
        7) show_monitoring_menu ;;
        8) show_maintenance_menu ;;
        9) 
            info "Exiting..."
            exit 0
            ;;
        *) 
            error "Invalid choice: $choice"
            show_menu
            ;;
    esac
}

# ===== UTILS MENU =====
show_utils_menu() {
    echo
    echo -e "\033[1;36m=== Utils Menu ===\033[0m"
    echo
    echo "1) Fix/Enforce Standard Permissions"
    echo "2) Change Primary Domain"
    echo "3) Remove WordPress (Nuke System)"
    echo "4) Back to Main Menu"
    echo
    read -p "Enter your choice [1-4]: " choice
    echo
    
    case $choice in
        1) fix_permissions ;;
        2) change_primary_domain ;;
        3) nuke_all ;;
        4) show_menu ;;
        *) 
            error "Invalid choice: $choice"
            show_utils_menu
            ;;
    esac
}

# ===== MONITORING MENU =====
show_monitoring_menu() {
    echo
    echo -e "\033[1;35m=== Monitoring Menu ===\033[0m"
    echo
    echo "Monitoring features will be implemented in future updates."
    echo
    echo "Planned features:"
    echo "• System resource monitoring"
    echo "• Website uptime monitoring"
    echo "• Security event monitoring"
    echo "• Performance metrics"
    echo
    echo "1) Back to Main Menu"
    echo
    read -p "Enter your choice [1]: " choice
    echo
    
    case $choice in
        1) show_menu ;;
        *) 
            error "Invalid choice: $choice"
            show_monitoring_menu
            ;;
    esac
}

# ===== MAINTENANCE MENU =====
show_maintenance_menu() {
    echo
    echo -e "\033[1;33m=== Maintenance Menu ===\033[0m"
    echo
    echo "Maintenance features will be implemented in future updates."
    echo
    echo "Planned features:"
    echo "• WordPress core updates"
    echo "• Plugin/theme updates"
    echo "• Database optimization"
    echo "• Log rotation and cleanup"
    echo "• SSL certificate renewal"
    echo
    echo "1) Back to Main Menu"
    echo
    read -p "Enter your choice [1]: " choice
    echo
    
    case $choice in
        1) show_menu ;;
        *) 
            error "Invalid choice: $choice"
            show_maintenance_menu
            ;;
    esac
}

# ===== UTILITY FUNCTIONS =====
fix_permissions() {
    info "=== Fix/Enforce Standard Permissions ==="
    echo
    
    # Load required modules
    for module in utils.sh; do
        load_module "$module"
    done
    
    echo "This will apply the standardized permission model to your WordPress installation:"
    echo "• Base permissions: 644 files, 755 directories"
    echo "• WordPress files: wpuser:wordpress ownership"
    echo "• Writable dirs: php-fpm:wordpress with setgid (2775)"
    echo "• Backup/log dirs: restricted access (2750)"
    echo "• Sensitive config: wp-config.php (640)"
    echo
    
    if ! command -v confirm &>/dev/null; then
        echo -n "Apply standard permissions? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            show_utils_menu
            return
        fi
    else
        if ! confirm "Apply standard permissions?" N; then
            show_utils_menu
            return
        fi
    fi
    
    if enforce_standard_permissions; then
        success "✓ Standard permissions applied successfully"
    else
        error "Failed to apply permissions"
    fi
    
    echo
    echo "Press Enter to continue..."
    read
    show_utils_menu
}

change_primary_domain() {
    info "=== Change Primary Domain ==="
    echo
    
    # Load required modules
    for module in utils.sh config.sh nginx.sh ssl.sh wordpress.sh; do
        load_module "$module"
    done
    
    local current_domain=$(load_state "DOMAIN")
    if [ -z "$current_domain" ]; then
        error "No current domain found in configuration"
        echo "Press Enter to continue..."
        read
        show_utils_menu
        return
    fi
    
    echo "Current domain: $current_domain"
    echo
    echo "Enter new domain name (without www):"
    read -p "> " new_domain
    
    if [ -z "$new_domain" ]; then
        error "Domain cannot be empty"
        echo "Press Enter to continue..."
        read
        show_utils_menu
        return
    fi
    
    if ! validate_domain "$new_domain"; then
        error "Invalid domain format"
        echo "Press Enter to continue..."
        read
        show_utils_menu
        return
    fi
    
    echo
    echo "This will update:"
    echo "• WordPress site URL and home URL"
    echo "• Nginx server configuration"
    echo "• SSL certificates (Let's Encrypt)"
    echo "• WordPress configuration files"
    echo
    echo "From: $current_domain"
    echo "To:   $new_domain"
    echo
    
    if ! command -v confirm &>/dev/null; then
        echo -n "Proceed with domain change? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            show_utils_menu
            return
        fi
    else
        if ! confirm "Proceed with domain change?" N; then
            show_utils_menu
            return
        fi
    fi
    
    if update_primary_domain "$current_domain" "$new_domain"; then
        success "✓ Domain changed successfully from $current_domain to $new_domain"
        save_state "DOMAIN" "$new_domain"
    else
        error "Failed to change domain"
    fi
    
    echo
    echo "Press Enter to continue..."
    read
    show_utils_menu
}

update_primary_domain() {
    local old_domain=$1
    local new_domain=$2
    local wp_root=$(load_state "WP_ROOT")
    
    info "Updating domain from $old_domain to $new_domain..."
    
    # Update WordPress URLs
    if [ -f "$wp_root/wp-config.php" ]; then
        info "Updating WordPress URLs..."
        sudo -u wpuser wp --path="$wp_root" option update home "https://$new_domain" 2>/dev/null || true
        sudo -u wpuser wp --path="$wp_root" option update siteurl "https://$new_domain" 2>/dev/null || true
    fi
    
    # Update nginx configuration
    if [ -f "/etc/nginx/sites-available/$old_domain" ]; then
        info "Updating nginx configuration..."
        sudo sed -i "s/$old_domain/$new_domain/g" "/etc/nginx/sites-available/$old_domain"
        sudo mv "/etc/nginx/sites-available/$old_domain" "/etc/nginx/sites-available/$new_domain"
        
        if [ -L "/etc/nginx/sites-enabled/$old_domain" ]; then
            sudo rm "/etc/nginx/sites-enabled/$old_domain"
            sudo ln -sf "/etc/nginx/sites-available/$new_domain" "/etc/nginx/sites-enabled/$new_domain"
        fi
        
        # Test nginx configuration
        if sudo nginx -t; then
            sudo systemctl reload nginx
            success "Nginx configuration updated"
        else
            error "Nginx configuration test failed"
            return 1
        fi
    fi
    
    # Update SSL certificates
    info "SSL certificates will need to be renewed for the new domain"
    info "Run: sudo certbot --nginx -d $new_domain -d www.$new_domain"
    
    return 0
}

# ===== MAIN EXECUTION =====
main() {
    # Handle command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG=1
                shift
                ;;
            --update)
                UPDATE_MODULES=1
                shift
                ;;
            --fresh)
                mode_fresh_install
                exit 0
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --debug     Enable debug output"
                echo "  --update    Force module updates"  
                echo "  --fresh     Run fresh installation without menu"
                echo "  --help      Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    touch "$LOG_FILE"
    info "WordPress Setup Script v${SCRIPT_VERSION} started"
    
    # Check for updates unless disabled
    if [ "${SKIP_UPDATE:-0}" != "1" ]; then
        check_update "$@"
    fi
    
    # Show menu
    show_menu
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"