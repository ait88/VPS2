#!/bin/bash
# setup-wordpress.sh - Modular WordPress installation with backup integration
# Version: 2.0.1
# GitHub: https://github.com/ait88/VPS

set -euo pipefail

# ===== CONFIGURATION SECTION =====
SCRIPT_VERSION="2.0.1"
SCRIPT_URL="https://raw.githubusercontent.com/ait88/VPS/main/setup-wordpress.sh"
STATE_FILE="$HOME/.wordpress_setup_state"
LOG_FILE="$HOME/wordpress_setup.log"
BACKUP_USER="wp-backup"
BACKUP_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKk1nsYyDbYzYL5UXEc8X9IDBIJECt9mQzy307M6h7p5"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== LOGGING FUNCTIONS =====
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@"
    log "SUCCESS" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@"
    log "WARNING" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@"
    log "ERROR" "$@"
}

# ===== SELF-UPDATE FUNCTION =====
check_and_update_script() {
    log_info "Checking for script updates..."
    
    # Download latest version to temp file
    local temp_script="/tmp/setup-wordpress-new.sh"
    
    if command -v curl &> /dev/null; then
        curl -sL "$SCRIPT_URL" -o "$temp_script" || {
            log_warning "Failed to check for updates"
            return 1
        }
    else
        log_error "curl is not installed. Cannot check for updates."
        return 1
    fi
    
    # Extract version from downloaded script
    local latest_version=$(grep "^SCRIPT_VERSION=" "$temp_script" | head -1 | cut -d'"' -f2)
    
    if [ -z "$latest_version" ]; then
        log_warning "Could not determine latest version"
        rm -f "$temp_script"
        return 1
    fi
    
    log_info "Current version: $SCRIPT_VERSION, Latest version: $latest_version"
    
    # Compare versions
    if [ "$latest_version" != "$SCRIPT_VERSION" ]; then
        log_info "New version available: $latest_version"
        echo -e "${YELLOW}Would you like to update to version $latest_version? [y/N]:${NC} "
        read -r update_confirm
        
        if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
            # Backup current script
            cp "$0" "$0.backup-$(date +%Y%m%d-%H%M%S)"
            
            # Replace with new version
            mv "$temp_script" "$0"
            chmod +x "$0"
            
            log_success "Script updated to version $latest_version"
            echo -e "${GREEN}Restarting with new version...${NC}"
            exec "$0" "$@"
        else
            log_info "Update skipped"
            rm -f "$temp_script"
        fi
    else
        log_success "Already running latest version"
        rm -f "$temp_script"
    fi
}

# ===== STATE MANAGEMENT =====
save_state() {
    local key=$1
    local value=$2
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Update or add the key-value pair
    if grep -q "^${key}=" "$STATE_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
    
    log_info "State saved: ${key}=${value}"
}

load_state() {
    local key=$1
    local default_value=${2:-""}
    
    if [ -f "$STATE_FILE" ]; then
        local value=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2-)
        echo "${value:-$default_value}"
    else
        echo "$default_value"
    fi
}

state_exists() {
    local key=$1
    [ -f "$STATE_FILE" ] && grep -q "^${key}=" "$STATE_FILE"
}

clear_state() {
    if [ -f "$STATE_FILE" ]; then
        mv "$STATE_FILE" "${STATE_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "State file backed up and cleared"
    fi
}

# ===== UTILITY FUNCTIONS =====
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            log_error "This script requires sudo privileges. Please run with sudo or configure passwordless sudo."
            exit 1
        fi
    fi
    log_info "Sudo privileges confirmed"
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            log_error "This script is designed for Ubuntu/Debian systems"
            exit 1
        fi
        log_info "Detected OS: $PRETTY_NAME"
    else
        log_error "Cannot determine OS. /etc/os-release not found"
        exit 1
    fi
}

generate_secure_password() {
    local length=${1:-24}
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+=' | head -c "$length"
}

validate_domain() {
    local domain=$1
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    
    if [[ $domain =~ $domain_regex ]]; then
        return 0
    else
        return 1
    fi
}

confirm_action() {
    local prompt=$1
    local default=${2:-N}
    
    if [ "$default" = "Y" ]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi
    
    echo -ne "${YELLOW}${prompt}${NC}"
    read -r response
    
    if [ -z "$response" ]; then
        response=$default
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# ===== CHECK EXISTING INSTALLATION =====
check_existing_installation() {
    log_info "Checking for existing WordPress installation..."
    
    local wp_exists=false
    local wp_locations=()
    
    # Check common WordPress locations
    for dir in /var/www/wordpress /var/www/html /home/*/public_html; do
        if [ -f "$dir/wp-config.php" ]; then
            wp_exists=true
            wp_locations+=("$dir")
        fi
    done
    
    # Check if setup was previously run
    if state_exists "WP_INSTALLED"; then
        local installed_path=$(load_state "WP_ROOT")
        if [ -n "$installed_path" ] && [ -f "$installed_path/wp-config.php" ]; then
            wp_exists=true
            wp_locations+=("$installed_path")
        fi
    fi
    
    if $wp_exists; then
        log_warning "Found existing WordPress installation(s):"
        printf '%s\n' "${wp_locations[@]}" | sort -u | while read -r location; do
            echo "  - $location"
        done
        save_state "EXISTING_WP_FOUND" "true"
        save_state "EXISTING_WP_PATHS" "$(printf '%s,' "${wp_locations[@]}")"
    else
        log_info "No existing WordPress installation found"
        save_state "EXISTING_WP_FOUND" "false"
    fi
    
    return 0
}

# ===== MODULE: PREFLIGHT CHECKS =====
01_preflight_checks() {
    log_info "=== Running Preflight Checks ==="
    
    # Skip if already completed
    if state_exists "PREFLIGHT_COMPLETED"; then
        log_info "Preflight checks already completed, skipping..."
        return 0
    fi
    
    # Check sudo access
    check_sudo
    
    # Check OS
    check_os
    
    # Check disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2097152 ]; then # Less than 2GB
        log_error "Insufficient disk space. At least 2GB required."
        exit 1
    fi
    log_info "Disk space check passed: $(df -h / | awk 'NR==2 {print $4}') available"
    
    # Check memory
    local total_mem=$(free -m | awk 'NR==2 {print $2}')
    if [ "$total_mem" -lt 512 ]; then
        log_warning "Low memory detected: ${total_mem}MB. Recommended: 1GB+"
    else
        log_info "Memory check passed: ${total_mem}MB total"
    fi
    
    # Check for conflicting services
    for service in apache2 lighttpd; do
        if sudo systemctl is-active --quiet $service 2>/dev/null; then
            log_error "Conflicting service detected: $service is running"
            if confirm_action "Stop and disable $service?"; then
                sudo systemctl stop $service
                sudo systemctl disable $service
                log_success "$service stopped and disabled"
            else
                log_error "Cannot continue with $service running"
                exit 1
            fi
        fi
    done
    
    # Check network connectivity
    if ! ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        log_error "No internet connectivity detected"
        exit 1
    fi
    log_info "Network connectivity check passed"
    
    save_state "PREFLIGHT_COMPLETED" "true"
    log_success "Preflight checks completed successfully"
}

# ===== MAIN MENU =====
show_main_menu() {
    local existing_wp=$(load_state "EXISTING_WP_FOUND" "false")
    
    echo
    echo -e "${BLUE}=== WordPress Setup Script v${SCRIPT_VERSION} ===${NC}"
    echo
    
    if [ "$existing_wp" = "true" ]; then
        echo -e "${YELLOW}Existing WordPress installation detected${NC}"
        echo
        echo "Please select an option:"
        echo "1) Reconfigure existing installation"
        echo "2) Create new installation (different location)"
        echo "3) Reset (backup and fresh install)"
        echo "4) Restore from backup"
        echo "5) Exit"
    else
        echo "Please select installation type:"
        echo "1) Fresh WordPress installation"
        echo "2) Import existing WordPress site"
        echo "3) Restore from backup"
        echo "4) Exit"
    fi
    
    echo
    read -p "Enter your choice: " choice
    echo
    
    return $choice
}

# ===== MODULE: INSTALL DEPENDENCIES =====
02_install_dependencies() {
    log_info "=== Installing Dependencies ==="
    
    if state_exists "DEPENDENCIES_INSTALLED"; then
        log_info "Dependencies already installed, skipping..."
        return 0
    fi
    
    # Update package lists
    log_info "Updating package lists..."
    sudo apt-get update -qq || { log_error "Failed to update package lists"; exit 1; }
    
    # Detect PHP version
    local php_version="8.2"
    if command -v php &>/dev/null; then
        php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
        log_info "Detected PHP $php_version"
    fi
    
    # Core packages
    local packages=(
        # Web stack
        nginx
        mariadb-server
        "php${php_version}-fpm"
        "php${php_version}-mysql"
        "php${php_version}-xml"
        "php${php_version}-curl"
        "php${php_version}-gd"
        "php${php_version}-mbstring"
        "php${php_version}-zip"
        "php${php_version}-imagick"
        "php${php_version}-intl"
        "php${php_version}-bcmath"
        # Tools
        curl wget unzip rsync
        # Security
        fail2ban certbot python3-certbot-nginx
        # Monitoring
        htop iotop
    )
    
    log_info "Installing packages..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" || {
        log_error "Package installation failed"
        exit 1
    }
    
    # Install WP-CLI
    if ! command -v wp &>/dev/null; then
        log_info "Installing WP-CLI..."
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
    fi
    
    # Verify critical services
    for service in nginx "php${php_version}-fpm" mariadb; do
        sudo systemctl is-enabled --quiet $service || sudo systemctl enable $service
        sudo systemctl is-active --quiet $service || sudo systemctl start $service
    done
    
    save_state "DEPENDENCIES_INSTALLED" "true"
    save_state "PHP_VERSION" "$php_version"
    log_success "Dependencies installed successfully"
}

# ===== MODULE: INTERACTIVE CONFIGURATION =====
03_interactive_config() {
    log_info "=== Configuration Setup ==="
    
    # WordPress Configuration
    echo -e "\n${BLUE}WordPress Configuration${NC}"
    
    read -p "WordPress system username [wpuser]: " WP_USER
    WP_USER="${WP_USER:-wpuser}"
    
    read -p "WordPress root directory [/var/www/wordpress]: " WP_ROOT
    WP_ROOT="${WP_ROOT:-/var/www/wordpress}"
    
    # Domain Configuration
    while true; do
        read -p "Primary domain (e.g., example.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        else
            log_error "Invalid domain format"
        fi
    done
    
    read -p "Include www alias? [Y/n]: " INCLUDE_WWW
    INCLUDE_WWW="${INCLUDE_WWW:-Y}"
    
    read -p "Admin email [$WP_USER@$DOMAIN]: " ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-$WP_USER@$DOMAIN}"
    
    # Database Configuration
    echo -e "\n${BLUE}Database Configuration${NC}"
    
    read -p "Database name [wp_${DOMAIN//[.-]/_}]: " DB_NAME
    DB_NAME="${DB_NAME:-wp_${DOMAIN//[.-]/_}}"
    
    read -p "Database user [${DB_NAME}_user]: " DB_USER
    DB_USER="${DB_USER:-${DB_NAME}_user}"
    
    DB_PASS=$(generate_secure_password)
    echo "Generated database password: ${GREEN}${DB_PASS}${NC}"
    
    # Save all configuration
    local configs=(
        "WP_USER:$WP_USER"
        "WP_ROOT:$WP_ROOT"
        "DOMAIN:$DOMAIN"
        "INCLUDE_WWW:$INCLUDE_WWW"
        "ADMIN_EMAIL:$ADMIN_EMAIL"
        "DB_NAME:$DB_NAME"
        "DB_USER:$DB_USER"
        "DB_PASS:$DB_PASS"
    )
    
    for config in "${configs[@]}"; do
        IFS=: read -r key value <<< "$config"
        save_state "$key" "$value"
    done
    
    log_success "Configuration saved"
}

# ===== MODULE: SETUP USERS =====
04_setup_users() {
    log_info "=== Setting Up Users ==="
    
    if state_exists "USERS_CONFIGURED"; then
        log_info "Users already configured, skipping..."
        return 0
    fi
    
    local wp_user=$(load_state "WP_USER")
    local wp_root=$(load_state "WP_ROOT")
    
    # Create WordPress system user
    if ! id "$wp_user" &>/dev/null; then
        log_info "Creating WordPress user: $wp_user"
        sudo useradd -r -s /bin/bash -d "/home/$wp_user" -m "$wp_user"
    fi
    
    # Create backup user
    if ! id "$BACKUP_USER" &>/dev/null; then
        log_info "Creating backup user: $BACKUP_USER"
        sudo useradd -r -s /bin/bash -d "/home/$BACKUP_USER" -m "$BACKUP_USER"
    fi
    
    # Setup backup SSH access
    sudo mkdir -p "/home/$BACKUP_USER/.ssh"
    echo "$BACKUP_SSH_KEY" | sudo tee "/home/$BACKUP_USER/.ssh/authorized_keys" > /dev/null
    
    # Prompt for additional backup keys
    while confirm_action "Add another backup worker SSH key?" N; do
        read -p "Paste SSH public key: " extra_key
        echo "$extra_key" | sudo tee -a "/home/$BACKUP_USER/.ssh/authorized_keys" > /dev/null
    done
    
    # Set permissions
    sudo chmod 700 "/home/$BACKUP_USER/.ssh"
    sudo chmod 600 "/home/$BACKUP_USER/.ssh/authorized_keys"
    sudo chown -R "$BACKUP_USER:$BACKUP_USER" "/home/$BACKUP_USER"
    
    # Add backup user to WordPress group for read access
    sudo usermod -a -G "$wp_user" "$BACKUP_USER"
    
    # Create web root
    sudo mkdir -p "$wp_root"
    sudo chown "$wp_user:$wp_user" "$wp_root"
    sudo chmod 750 "$wp_root"
    
    save_state "USERS_CONFIGURED" "true"
    log_success "Users configured successfully"
}

# ===== MODULE: CONFIGURE MARIADB =====
05_configure_mariadb() {
    log_info "=== Configuring MariaDB ==="
    
    if state_exists "MARIADB_CONFIGURED"; then
        log_info "MariaDB already configured, skipping..."
        return 0
    fi
    
    local db_name=$(load_state "DB_NAME")
    local db_user=$(load_state "DB_USER")
    local db_pass=$(load_state "DB_PASS")
    
    # Secure MariaDB installation
    log_info "Securing MariaDB installation..."
    sudo mysql -e "UPDATE mysql.user SET Password=PASSWORD('$(generate_secure_password)') WHERE User='root';"
    sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
    sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    sudo mysql -e "DROP DATABASE IF EXISTS test;"
    sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    
    # Create WordPress database and user
    log_info "Creating WordPress database: $db_name"
    sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS $db_name DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Optimize MariaDB settings for WordPress
    sudo tee /etc/mysql/mariadb.conf.d/60-wordpress.cnf > /dev/null <<EOF
[mysqld]
# WordPress optimizations
max_connections = 100
key_buffer_size = 32M
max_allowed_packet = 64M
table_open_cache = 256
sort_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 4M
myisam_sort_buffer_size = 32M
thread_cache_size = 8
query_cache_size = 32M
query_cache_limit = 2M

# InnoDB settings
innodb_buffer_pool_size = 128M
innodb_log_file_size = 32M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
EOF
    
    sudo systemctl restart mariadb
    
    save_state "MARIADB_CONFIGURED" "true"
    log_success "MariaDB configured successfully"
}

# ===== MAIN EXECUTION =====
main() {
    log_info "WordPress Setup Script v${SCRIPT_VERSION} started"
    
    check_and_update_script "$@"
    01_preflight_checks
    check_existing_installation
    
    show_main_menu
    local choice=$?
    
    case $choice in
        1)
            if [ "$(load_state "EXISTING_WP_FOUND")" = "true" ]; then
                log_info "Starting reconfiguration..."
                # mode_reconfigure
            else
                log_info "Starting fresh installation..."
                02_install_dependencies
                03_interactive_config
                04_setup_users
                05_configure_mariadb
                # Continue with more modules...
            fi
            ;;
        2)
            if [ "$(load_state "EXISTING_WP_FOUND")" = "true" ]; then
                log_info "Starting new installation..."
                02_install_dependencies
                03_interactive_config
                04_setup_users
                05_configure_mariadb
                # mode_fresh_install
            else
                log_info "Starting import..."
                02_install_dependencies
                03_interactive_config
                04_setup_users
                05_configure_mariadb
                # mode_import_site
            fi
            ;;
        3)
            if [ "$(load_state "EXISTING_WP_FOUND")" = "true" ]; then
                log_info "Starting reset..."
                # mode_reset
            else
                log_info "Starting restore..."
                02_install_dependencies
                04_setup_users
                05_configure_mariadb
                # mode_restore_backup
            fi
            ;;
        4|5)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# ===== SCRIPT ENTRY POINT =====
# Trap errors
trap 'log_error "Script failed at line $LINENO with exit code $?"' ERR

# Create log file
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Run main function
main "$@"