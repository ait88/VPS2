#!/bin/bash
# setup-wordpress.sh - Modular WordPress Installation Manager
# GitHub: https://github.com/ait88/VPS2

set -euo pipefail

# ===== CONFIGURATION =====
SCRIPT_VERSION="3.1.5"
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
    echo -e "\033[0;34m[INFO]\033[0m $@" >&2
    log_to_file "INFO" "$@"
}

success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $@" >&2
    log_to_file "SUCCESS" "$@"
}

warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $@" >&2
    log_to_file "WARNING" "$@"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $@" >&2
    log_to_file "ERROR" "$@"
}

debug() {
    # Only show if DEBUG=1
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "\033[0;90m[DEBUG]\033[0m $@" >&2
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
    "sftp.sh"            # SFTP user setup
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

# Force update - unconditionally updates setup-wordpress.sh and all lib modules
force_update() {
    info "=== Force Update ==="
    echo
    echo "This will update:"
    echo "  • setup-wordpress.sh (main script)"
    echo "  • All library modules in wordpress-mgmt/lib/"
    echo

    if ! confirm "Proceed with force update?" Y; then
        info "Update cancelled"
        return 0
    fi

    local failed=0

    # Step 1: Update main script
    info "Updating setup-wordpress.sh..."
    local temp_script="/tmp/setup-wordpress-new.sh"

    if curl -fsSL "$SCRIPT_URL" -o "$temp_script" 2>/dev/null; then
        local new_version=$(grep "^SCRIPT_VERSION=" "$temp_script" | head -1 | cut -d'"' -f2)

        # Create backup
        cp "$0" "$0.backup-$(date +%Y%m%d-%H%M%S)"

        # Replace script
        mv "$temp_script" "$0"
        chmod +x "$0"

        success "✓ setup-wordpress.sh updated (v${SCRIPT_VERSION} → v${new_version:-unknown})"
    else
        error "✗ Failed to download setup-wordpress.sh"
        failed=1
    fi

    # Step 2: Update all lib modules
    info "Updating library modules..."
    local module_count=0
    local module_failed=0

    for module in "${MODULES[@]}"; do
        local module_path="$LIB_DIR/$module"
        local module_url="$BASE_URL/lib/$module"

        if curl -fsSL "$module_url" -o "$module_path" 2>/dev/null; then
            chmod +x "$module_path"
            ((module_count++))
            debug "✓ Updated: $module"
        else
            error "✗ Failed to update: $module"
            ((module_failed++))
            failed=1
        fi
    done

    echo
    if [ $failed -eq 0 ]; then
        success "=== Force Update Complete ==="
        echo "Updated: setup-wordpress.sh + $module_count modules"
        echo
        info "Restarting script with updated version..."
        exec "$0" "$@"
    else
        warning "=== Force Update Completed with Errors ==="
        echo "Updated: $module_count modules"
        echo "Failed: $module_failed modules"
        echo
        warning "Some updates failed. Check network connection and try again."
        return 1
    fi
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
    verify_wordpress_installation || {
        error "WordPress installation failed verification"
        exit 1
    }
    setup_ssl
    apply_security
    setup_sftp_user
    setup_backup_system

    # Load security module if not already loaded
    if ! command -v show_completion_summary >/dev/null 2>&1; then
        load_module "security.sh" || {
            error "Failed to load security module for completion summary"
            exit 1
        }
    fi

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
    sudo systemctl stop "$(get_php_service)" 2>/dev/null || true
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

    # Remove database state completely
    info "Clearing database state..."
    remove_state "DATABASE_CONFIGURED"
    remove_state "DB_ROOT_PASS"

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

    # Clean up package state overrides to prevent reinstall issues
    info "Cleaning up package state overrides..."
    sudo dpkg-statoverride --list | grep -E "(redis|mysql|php)" | while read perm owner group path; do
    sudo dpkg-statoverride --remove "$path" 2>/dev/null || true
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
    sudo rm -f "$(get_php_fpm_pool_dir)/wordpress.conf" 2>/dev/null || true
    # Also clean up any other PHP versions to ensure complete cleanup
    sudo rm -f /etc/php/*/fpm/pool.d/wordpress.conf 2>/dev/null || true

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

# ===== RESUME/RE-RUN FUNCTIONS =====
show_resume_menu() {
    echo
    echo -e "\033[1;32m=== Resume/Re-run Menu ===\033[0m"
    echo
    echo "1) Resume from last failed step"
    echo "2) Re-run a specific setup step"
    echo "3) Back to Main Menu"
    echo
    read -p "Enter your choice [1-3]: " choice
    echo

    case $choice in
        1) resume_from_last_step ;;
        2) rerun_specific_step ;;
        3) show_menu ;;
        *)
            error "Invalid choice: $choice"
            show_resume_menu
            ;;
    esac
}

resume_from_last_step() {
    info "=== Resuming from last failed step ==="
    if [ ! -f "$STATE_FILE" ]; then
        error "No setup_state file found. Cannot resume."
        return
    fi
    # Load all modules to ensure functions are available
    for module in "${MODULES[@]}"; do
        load_module "$module"
    done
    # complete_wordpress_setup is in wordpress.sh and contains state checks
    complete_wordpress_setup
}

rerun_specific_step() {
    echo
    echo -e "\033[1;33m=== Re-run Specific Step ===\033[0m"
    echo "This will clear the completion flag for a step and re-run it."
    echo
    echo "1) Re-install Packages"
    echo "2) Re-configure Users"
    echo "3) Re-configure Database"
    echo "4) Re-configure Nginx"
    echo "5) Re-configure SSL"
    echo "6) Re-apply Security Hardening"
    echo "7) Re-configure Backups"
    echo "8) Back to Resume Menu"
    echo
    read -p "Enter your choice [1-8]: " choice
    echo

    # Load all modules first
    for module in "${MODULES[@]}"; do
        load_module "$module"
    done

    local step_chosen=false
    case $choice in
        1) remove_state "PACKAGES_INSTALLED"; install_packages; step_chosen=true ;;
        2) remove_state "USERS_CONFIGURED"; setup_users; step_chosen=true ;;
        3) remove_state "DATABASE_CONFIGURED"; setup_database; step_chosen=true ;;
        4) remove_state "NGINX_CONFIGURED"; configure_nginx; step_chosen=true ;;
        5) remove_state "SSL_CONFIGURED"; setup_ssl; step_chosen=true ;;
        6) remove_state "SECURITY_CONFIGURED"; apply_security; step_chosen=true ;;
        7) remove_state "BACKUP_CONFIGURED"; setup_backup_system; step_chosen=true ;;
        8) show_resume_menu ;;
        *)
            error "Invalid choice: $choice"
            rerun_specific_step
            ;;
    esac

    if [ "$step_chosen" = true ]; then
        if confirm "Continue with the rest of the setup from here?" Y; then
            complete_wordpress_setup
        else
            show_resume_menu
        fi
    fi
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
    echo "4) Resume/Re-run Failed Setup"
    echo
    echo "Management & Updates:"
    echo "5) Utils Menu (Permissions, Domain Change, Nuke)"
    echo "6) Monitoring Menu"
    echo "7) Maintenance Menu"
    echo "8) Force Update (script + all modules)"
    echo
    echo "9) Exit"
    echo
    read -p "Enter your choice [1-9]: " choice
    echo

    case $choice in
        1) mode_fresh_install ;;
        2) mode_import_site ;;
        3) mode_restore_backup ;;
        4) show_resume_menu ;;
        5) show_utils_menu ;;
        6) show_monitoring_menu ;;
        7) show_maintenance_menu ;;
        8) force_update ;;
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
    echo "3) Backup Management (Pin, Retention, etc.)"
    echo "4) PHP Version Management"
    echo "5) Remove WordPress (Nuke System)"
    echo "6) Test SSH Import Connectivity"
    echo "7) Migrate Cron Jobs from Remote Server"
    echo "8) Generate Debug Report (for troubleshooting)"
    echo "9) Back to Main Menu"
    echo
    read -p "Enter your choice [1-9]: " choice
    echo

    case $choice in
        1) fix_permissions ;;
        2) change_primary_domain ;;
        3) show_backup_menu ;;
        4) manage_php_version ;;
        5) nuke_all ;;
        6) test_ssh_import && show_utils_menu ;;
        7) migrate_cron_jobs && show_utils_menu ;;
        8) run_debug_report ;;
        9) show_menu ;;
        *)
            error "Invalid choice: $choice"
            show_utils_menu
            ;;
    esac
}

# ===== PHP VERSION MANAGEMENT =====
manage_php_version() {
    echo
    echo -e "\033[1;36m=== PHP Version Management ===\033[0m"
    echo
    
    # Load utils module
    load_module "utils.sh"
    
    local current_version=$(get_php_version)
    echo "Current PHP version: $current_version"
    echo
    
    # Show available versions
    echo "Available PHP versions:"
    apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | \
        grep -oP 'php\K[0-9]+\.[0-9]+' | sort -V -u | nl -w2 -s') '
    
    echo
    echo "1) Change PHP version"
    echo "2) Show current PHP configuration"
    echo "3) Back to Utils Menu"
    echo
    read -p "Enter your choice [1-3]: " choice
    echo
    
    case $choice in
        1)
            read -p "Enter new PHP version (e.g., 8.4): " new_version
            if [ -n "$new_version" ]; then
                update_php_version "$new_version"
            fi
            ;;
        2)
            info "PHP Configuration:"
            echo "  Version: $(php -v | head -1)"
            echo "  FPM Socket: $(load_state "PHP_FPM_SOCKET")"
            echo "  Service: php${current_version}-fpm"
            echo "  Pool Config: /etc/php/${current_version}/fpm/pool.d/"
            ;;
        3)
            show_utils_menu
            return
            ;;
    esac
    
    echo
    echo "Press Enter to continue..."
    read
    manage_php_version
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

# ===== BACKUP MANAGEMENT MENU =====
show_backup_menu() {
    echo
    echo -e "\033[1;32m=== Backup Management Menu ===\033[0m"
    echo
    echo "1) List all backups"
    echo "2) Pin a backup (protect from deletion)"
    echo "3) Unpin a backup"
    echo "4) Show backup statistics"
    echo "5) Update backup script (apply retention changes)"
    echo "6) Back to Utils Menu"
    echo
    read -p "Enter your choice [1-6]: " choice
    echo

    case $choice in
        1) list_backups ;;
        2) pin_backup ;;
        3) unpin_backup ;;
        4) show_backup_stats ;;
        5) update_backup_script ;;
        6) show_utils_menu ;;
        *)
            error "Invalid choice: $choice"
            show_backup_menu
            ;;
    esac
}

list_backups() {
    info "=== Available Backups ==="
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    local backup_dirs=(
        "/home/$backup_user/backups/daily"
        "/home/$backup_user/backups/weekly"
        "/home/$backup_user/backups/monthly"
    )
    
    for dir in "${backup_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local type=$(basename "$dir")
            echo
            echo "━━━ ${type^^} Backups ━━━"
            
            local backups=$(sudo -u "$backup_user" ls -1t "$dir"/*.tar.gz 2>/dev/null || true)
            
            if [ -z "$backups" ]; then
                echo "  No backups found"
                continue
            fi
            
            echo "$backups" | while read -r backup; do
                local basename=$(basename "$backup")
                local size=$(sudo du -h "$backup" | cut -f1)
                local date=$(sudo stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d. -f1)
                local pinned=""
                
                if [ -f "${backup}.pinned" ]; then
                    pinned=" [PINNED]"
                fi
                
                echo "  📦 $basename ($size)"
                echo "     Created: $date$pinned"
            done
        fi
    done
    
    echo
    echo "Press Enter to continue..."
    read
    show_backup_menu
}

pin_backup() {
    info "=== Pin a Backup ==="
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    
    # Show available backups
    echo
    echo "Available backups:"
    sudo -u "$backup_user" find /home/$backup_user/backups -name "*.tar.gz" -type f | \
        grep -v ".pinned" | \
        nl -w2 -s') '
    
    echo
    read -p "Enter backup number to pin (or 0 to cancel): " selection
    
    if [ "$selection" = "0" ]; then
        show_backup_menu
        return
    fi
    
    local backup_file=$(sudo -u "$backup_user" find /home/$backup_user/backups -name "*.tar.gz" -type f | \
        grep -v ".pinned" | \
        sed -n "${selection}p")
    
    if [ -z "$backup_file" ]; then
        error "Invalid selection"
    else
        sudo -u "$backup_user" touch "${backup_file}.pinned"
        success "Backup pinned: $(basename "$backup_file")"
    fi
    
    echo
    echo "Press Enter to continue..."
    read
    show_backup_menu
}

unpin_backup() {
    info "=== Unpin a Backup ==="
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    
    # Show pinned backups
    echo
    echo "Pinned backups:"
    local pinned_files=$(sudo -u "$backup_user" find /home/$backup_user/backups -name "*.tar.gz.pinned" -type f)
    
    if [ -z "$pinned_files" ]; then
        warning "No pinned backups found"
        echo
        echo "Press Enter to continue..."
        read
        show_backup_menu
        return
    fi
    
    echo "$pinned_files" | sed 's/.pinned$//' | nl -w2 -s') ' | sed 's|.*/||'
    
    echo
    read -p "Enter backup number to unpin (or 0 to cancel): " selection
    
    if [ "$selection" = "0" ]; then
        show_backup_menu
        return
    fi
    
    local pin_file=$(echo "$pinned_files" | sed -n "${selection}p")
    
    if [ -z "$pin_file" ]; then
        error "Invalid selection"
    else
        sudo -u "$backup_user" rm -f "$pin_file"
        success "Backup unpinned: $(basename "$pin_file" .pinned)"
    fi
    
    echo
    echo "Press Enter to continue..."
    read
    show_backup_menu
}

show_backup_stats() {
    info "=== Backup Statistics ==="
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    local retention=$(load_state "BACKUP_RETENTION_COUNT" "2")
    
    echo
    echo "Configuration:"
    echo "  Retention Count: $retention backups"
    echo
    
    for type in daily weekly monthly; do
        local dir="/home/$backup_user/backups/$type"
        if [ -d "$dir" ]; then
            local total=$(sudo -u "$backup_user" ls -1 "$dir"/*.tar.gz 2>/dev/null | wc -l)
            local pinned=$(sudo -u "$backup_user" ls -1 "$dir"/*.tar.gz.pinned 2>/dev/null | wc -l)
            local size=$(sudo du -sh "$dir" 2>/dev/null | cut -f1)
            
            echo "${type^} backups:"
            echo "  Total: $total ($pinned pinned)"
            echo "  Size: $size"
            echo
        fi
    done
    
    echo "Press Enter to continue..."
    read
    show_backup_menu
}

update_backup_script() {
    info "=== Update Backup Script ==="
    
    # Load modules
    for module in utils.sh backup.sh; do
        load_module "$module"
    done
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    local current_retention=$(load_state "BACKUP_RETENTION_COUNT" "2")
    
    echo
    echo "Current retention: $current_retention backups"
    echo
    
if confirm "Update retention count?" N; then
    echo -n "New retention count [2-5] [$current_retention]: "
    read -r new_retention
    new_retention="${new_retention:-$current_retention}"
        
        if [[ "$new_retention" =~ ^[2-5]$ ]]; then
            save_state "BACKUP_RETENTION_COUNT" "$new_retention"
            info "Retention updated to: $new_retention"
        else
            error "Invalid retention count (must be 2-5)"
            show_backup_menu
            return
        fi
    fi
    
    if confirm "Apply backup script updates to running system?" Y; then
        info "Updating backup scripts..."
        
        # Update config file
        sudo tee "/home/$backup_user/.backup_config" >/dev/null <<EOF
# Backup configuration - Updated $(date)
DOMAIN="$(load_state "DOMAIN")"
WP_ROOT="$(load_state "WP_ROOT")"
DB_NAME="$(load_state "DB_NAME")"
BACKUP_USER="$backup_user"
BACKUP_DIR="/home/$backup_user/backups"
RETENTION_COUNT="$(load_state "BACKUP_RETENTION_COUNT")"
EOF
        
        # Reinstall backup scripts
        install_backup_scripts
        
        success "Backup scripts updated successfully"
        info "Next scheduled backup will use new retention: $(load_state "BACKUP_RETENTION_COUNT")"
    fi
    
    echo
    echo "Press Enter to continue..."
    read
    show_backup_menu
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

run_debug_report() {
    info "=== Generate Debug Report ==="
    echo

    # Load required modules
    for module in utils.sh; do
        load_module "$module"
    done

    echo "This will generate an anonymized debug report containing:"
    echo "• System information (OS, memory, disk, CPU)"
    echo "• Service status (nginx, PHP-FPM, MariaDB, Redis, Fail2ban)"
    echo "• PHP configuration and modules"
    echo "• WordPress status and plugins"
    echo "• Anonymized state file contents"
    echo "• Permission audit"
    echo "• Recent log entries (anonymized)"
    echo
    echo "All sensitive data (domains, IPs, emails, passwords) will be redacted."
    echo

    if ! command -v confirm &>/dev/null; then
        echo -n "Generate debug report? [Y/n]: "
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Operation cancelled."
            show_utils_menu
            return
        fi
    else
        if ! confirm "Generate debug report?" Y; then
            show_utils_menu
            return
        fi
    fi

    generate_debug_report

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

migrate_cron_jobs() {
    info "=== Migrate Cron Jobs from Remote Server ==="

    # Load required modules
    for module in utils.sh wordpress.sh; do
        load_module "$module"
    done

    # Get SSH credentials
    ensure_sshpass || return 1
    get_ssh_credentials || return 1
    test_ssh_connection || return 1

    # --- Get remote WordPress path and crontab ---
    local remote_wp_dir=$(discover_and_select_wordpress)
    if [ -z "$remote_wp_dir" ]; then
        error "Could not determine remote WordPress directory. Aborting."
        return 1
    fi
    info "Remote WordPress path detected: $remote_wp_dir"

    info "Fetching remote cron jobs for user '$SSH_USER'..."
    local remote_cron=$(sshpass -p "$SSH_PASS" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" 'crontab -l 2>/dev/null')

    # --- Get local WordPress path ---
    local local_wp_dir=$(load_state "WP_ROOT")
    if [ -z "$local_wp_dir" ]; then
        error "Could not determine local WordPress directory (WP_ROOT). Aborting."
        return 1
    fi

    # --- Filter out non-job lines from the crontab ---
    local filtered_cron=$(echo "$remote_cron" | grep -vE '^(#|MAILTO=|SHELL=|$)')

    if [ -z "$filtered_cron" ]; then
        success "No actionable cron jobs found for remote user. Nothing to migrate."
        return 0
    fi

    # --- Get timezone information ---
    info "Fetching timezone information..."
    local remote_tz_string=$(sshpass -p "$SSH_PASS" ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" 'date +"%z"')
    local local_tz_string=$(date +"%z")

    offset_to_minutes() {
        local offset=$1
        local sign=${offset:0:1}
        local hours=${offset:1:2}
        local minutes=${offset:3:2}
        local total_minutes=$((10#$hours * 60 + 10#$minutes))
        [ "$sign" = "-" ] && total_minutes=$(( -total_minutes ))
        echo $total_minutes
    }

    local remote_offset=$(offset_to_minutes "$remote_tz_string")
    local local_offset=$(offset_to_minutes "$local_tz_string")
    local tz_diff_minutes=$((remote_offset - local_offset))

    info "Remote timezone offset: $remote_tz_string ($remote_offset minutes from UTC)"
    info "Local timezone offset:  $local_tz_string ($local_offset minutes from UTC)"
    info "Time difference: $tz_diff_minutes minutes"

    echo "Found the following remote cron jobs to process:"
    echo "------------------------------------"
    printf "%s\n" "$filtered_cron"
    echo "------------------------------------"

    if ! confirm "Proceed with migrating these cron jobs?" Y; then
        return 0
    fi

    local wp_user=$(load_state "WP_USER" "wpuser")

    # --- Loop, convert, and confirm each cron job ---
    # Use process substitution to avoid subshell issues with `read`
    while IFS= read -r line; do
        # Parse the cron line into schedule and command
        local schedule=$(echo "$line" | cut -d' ' -f1-5)
        local cmd=$(echo "$line" | cut -d' ' -f6-)

        # --- 1. Replace the path in the command ---
        local new_cmd=$(echo "$cmd" | sed "s|$remote_wp_dir|$local_wp_dir|g")

        # --- 2. Adjust the time schedule ---
        read -r min hour dom mon dow <<<"$schedule"
        local new_min=$min
        local new_hour=$hour
        local converted=false

        if [[ "$min" =~ ^[0-9]+$ && "$hour" =~ ^[0-9]+$ ]]; then
            local total_minutes=$((10#$hour * 60 + 10#$min))
            local new_total_minutes=$((total_minutes - tz_diff_minutes))
            new_total_minutes=$(((new_total_minutes % 1440 + 1440) % 1440))
            new_hour=$((new_total_minutes / 60))
            new_min=$((new_total_minutes % 60))
            converted=true
        fi

        local new_schedule="$new_min $new_hour $dom $mon $dow"
        local new_cron_line="$new_schedule $new_cmd"

        echo
        info "Processing cron job:"
        echo "  Remote:      $line"
        if [ "$converted" = true ]; then
            echo "  Suggested:   $new_cron_line"
            if confirm "Add this CONVERTED cron job for local user '$wp_user'?" Y; then
                 (sudo crontab -u "$wp_user" -l 2>/dev/null | grep -vF -- "$cmd"; echo "$new_cron_line") | sudo crontab -u "$wp_user" -
                 success "Cron job added."
            else
                 info "Skipping cron job."
            fi
        else
            warning "Cannot auto-convert complex schedule (e.g., */5, 1-5)."
            local unmodified_cron_line="$schedule $new_cmd" # Use schedule with NEW command
            echo "  Unmodified:  $unmodified_cron_line"
            if confirm "Add this cron job with UNMODIFIED time but UPDATED path for local user '$wp_user'?" Y; then
                 (sudo crontab -u "$wp_user" -l 2>/dev/null | grep -vF -- "$cmd"; echo "$unmodified_cron_line") | sudo crontab -u "$wp_user" -
                 success "Cron job added with updated path."
            else
                 info "Skipping cron job."
            fi
        fi
    done < <(echo "$filtered_cron")

    success "Cron job migration complete."
    echo
    info "Current cron jobs for user '$wp_user':"
    sudo crontab -u "$wp_user" -l
}

test_ssh_import() {
    info "=== SSH Import Test Mode ==="
    echo
    echo "This will test SSH connectivity and WordPress discovery."
    echo "No files will be transferred or imported."
    echo

    # Load required modules
    for module in utils.sh wordpress.sh; do
        load_module "$module"
    done

    # Ensure sshpass is available
    ensure_sshpass || return 1

    # Get SSH credentials
    get_ssh_credentials || return 1

    # Test connection
    test_ssh_connection || return 1

    # Discover WordPress sites
    local selected_wp_dir
    selected_wp_dir=$(discover_and_select_wordpress) || return 1

    # Extract database credentials
    local db_creds
    db_creds=$(extract_remote_db_creds "$selected_wp_dir") || return 1

    echo
    success "SSH import test completed successfully!"
    echo "Found WordPress at: $selected_wp_dir"
    echo "Database credentials extracted successfully"
    echo

    if confirm "Show extracted credentials?" N; then
        echo "$db_creds"
    fi
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
            --force-update)
                # Initialize logging first
                touch "$LOG_FILE"
                info "WordPress Setup Script v${SCRIPT_VERSION} started"
                force_update
                exit 0
                ;;
            --fresh)
                mode_fresh_install
                exit 0
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --debug         Enable debug output"
                echo "  --update        Force module re-download on load"
                echo "  --force-update  Update script and all modules from GitHub"
                echo "  --fresh         Run fresh installation without menu"
                echo "  --help          Show this help"
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
