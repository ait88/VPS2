#!/bin/bash
# wordpress-mgmt/lib/utils.sh - Common utility functions
# Version: 3.0.5

# ===== SYSTEM CHECKS =====
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            error "This script requires sudo privileges"
            exit 1
        fi
    fi
    debug "Sudo privileges confirmed"
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            error "This script requires Ubuntu/Debian"
            exit 1
        fi
        debug "Detected OS: $PRETTY_NAME"
    else
        error "Cannot determine OS"
        exit 1
    fi
}

# ===== PASSWORD GENERATION =====
generate_password() {
    local length=${1:-24}
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+=' | head -c "$length"
}

# ===== VALIDATION =====
validate_domain() {
    local domain=$1
    local regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    [[ $domain =~ $regex ]]
}

validate_email() {
    local email=$1
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    [[ $email =~ $regex ]]
}

# ===== PHP VERSION HELPERS =====
get_php_version() {
    # Get PHP version from state, with fallback to detection
    local php_version=$(load_state "PHP_VERSION" "")

    if [ -z "$php_version" ]; then
        # Try to detect from installed PHP
        if command -v php &>/dev/null; then
            php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
        else
            # Last resort: check for common PHP-FPM services
            for ver in 8.4 8.3 8.2 8.1; do
                if systemctl list-unit-files "php${ver}-fpm.service" &>/dev/null 2>&1; then
                    php_version="$ver"
                    break
                fi
            done
        fi
    fi

    echo "${php_version:-8.3}"
}

get_php_service() {
    # Get PHP-FPM service name
    local php_version=$(get_php_version)
    echo "php${php_version}-fpm"
}

get_php_fpm_pool_dir() {
    # Get PHP-FPM pool.d directory path
    local php_version=$(get_php_version)
    echo "/etc/php/${php_version}/fpm/pool.d"
}

get_php_fpm_conf_dir() {
    # Get PHP-FPM configuration directory
    local php_version=$(get_php_version)
    echo "/etc/php/${php_version}/fpm"
}

get_php_ini_path() {
    # Get PHP INI file path for FPM
    local php_version=$(get_php_version)
    echo "/etc/php/${php_version}/fpm/php.ini"
}

# ===== USER INTERACTION =====
# old confirm function changed due to error in cron import, leaving this here in case something breaks elsewhere.
#confirm() {
#    local prompt=$1
#    local default=${2:-N}
    
#    if [ "$default" = "Y" ]; then
#        prompt="${prompt} [Y/n]: "
#    else
#        prompt="${prompt} [y/N]: "
#    fi
    
#    echo -ne "\033[1;33m${prompt}\033[0m"
#    read -r response
    
#    response=${response:-$default}
#    [[ "$response" =~ ^[Yy]$ ]]
#}

confirm() {
    local prompt=$1
    local default=${2:-N}

    if [ "$default" = "Y" ]; then
        prompt="${prompt} [Y/n]: "
    else
        prompt="${prompt} [y/N]: "
    fi

    # Prompt the user on the terminal
    echo -ne "\033[1;33m${prompt}\033[0m" >&2

    # Read the response directly from the terminal device
    read -r response </dev/tty

    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

get_input() {
    local prompt=$1
    local default=${2:-""}
    local secret=${3:-false}
    local input=""
    
    if [ "$secret" = true ]; then
        echo -ne "\033[1;36m${prompt}\033[0m" >&2
        read -s input
        echo >&2
    else
        echo -ne "\033[1;36m${prompt}" >&2
        [ -n "$default" ] && echo -ne " [$default]" >&2
        echo -ne ":\033[0m " >&2
        read -r input
    fi
    
    echo "${input:-$default}"
}

# ===== SYSTEM RESOURCES =====
get_system_info() {
    local total_mem=$(free -m | awk 'NR==2 {print $2}')
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local cpu_cores=$(nproc)
    
    debug "System info: ${total_mem}MB RAM, ${available_space}KB disk, ${cpu_cores} cores"
    
    # Return as associative array values
    echo "TOTAL_MEM=$total_mem"
    echo "AVAILABLE_SPACE=$available_space" 
    echo "CPU_CORES=$cpu_cores"
}

# ===== SERVICE MANAGEMENT =====
restart_service() {
    local service=$1
    
    if sudo systemctl is-active --quiet "$service"; then
        info "Restarting $service..."
        sudo systemctl restart "$service"
        success "$service restarted"
    else
        warning "$service is not running"
        sudo systemctl start "$service"
        success "$service started"
    fi
}

enable_service() {
    local service=$1
    
    if ! sudo systemctl is-enabled --quiet "$service"; then
        sudo systemctl enable "$service"
        debug "Service enabled: $service"
    fi
}

# ===== FILE OPERATIONS =====
backup_file() {
    local file=$1
    local backup_suffix=${2:-".backup-$(date +%Y%m%d-%H%M%S)"}
    
    if [ -f "$file" ]; then
        sudo cp "$file" "${file}${backup_suffix}"
        debug "Backed up: $file -> ${file}${backup_suffix}"
        return 0
    else
        debug "File not found for backup: $file"
        return 1
    fi
}

secure_file() {
    local file=$1
    local owner=${2:-root:root}
    local perms=${3:-600}
    
    sudo chown "$owner" "$file"
    sudo chmod "$perms" "$file"
    debug "Secured file: $file ($owner:$perms)"
}

# ===== NETWORK CHECKS =====
check_connectivity() {
    local host=${1:-8.8.8.8}
    local timeout=${2:-5}
    
    if ping -c 1 -W "$timeout" "$host" &>/dev/null; then
        debug "Network connectivity verified"
        return 0
    else
        error "No network connectivity to $host"
        return 1
    fi
}

check_port() {
    local port=$1
    local host=${2:-localhost}
    
    if command -v nc &>/dev/null; then
        nc -z "$host" "$port" 2>/dev/null
    else
        # Fallback using bash
        timeout 1 bash -c "</dev/tcp/$host/$port" 2>/dev/null
    fi
}

# ===== CLEANUP =====
cleanup_temp() {
    local temp_dir=${1:-/tmp}
    find "$temp_dir" -name "wp-setup-*" -type f -mtime +1 -delete 2>/dev/null || true
    debug "Cleaned up temporary files"
}

# ===== PROGRESS INDICATION =====
show_progress() {
    local current=$1
    local total=$2
    local task=$3
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r\033[1;34m[%3d%%]\033[0m [" "$percent"
    printf "%*s" "$filled" | tr ' ' '='
    printf "%*s" "$empty" | tr ' ' '-'
    printf "] %s" "$task"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# ===== STANDARDIZED PERMISSIONS =====
enforce_standard_permissions() {
    local wp_root=$(load_state "WP_ROOT")
    local wp_user=$(load_state "WP_USER")
    
    info "Enforcing standardized permission model..."
    
    # Base ownership - everything owned by wpuser:wordpress
    sudo chown -R "$wp_user:wordpress" "$wp_root"
    
    # Base permissions
    sudo find "$wp_root" -type f -exec chmod 644 {} \;
    sudo find "$wp_root" -type d -exec chmod 755 {} \;
    
    # Sensitive configuration
    if [ -f "$wp_root/wp-config.php" ]; then
        sudo chmod 640 "$wp_root/wp-config.php"
    fi
    
    # Writable areas owned by php-fpm for write access
    local writable_dirs=("wp-content/uploads" "wp-content/cache" "wp-content/upgrade" "tmp")
    for dir in "${writable_dirs[@]}"; do
        if [ -d "$wp_root/$dir" ]; then
            sudo chown php-fpm:wordpress "$wp_root/$dir"
            sudo chmod 2775 "$wp_root/$dir"
        fi
    done
    
    # Restricted access areas
    local restricted_dirs=("backups" "logs")
    for dir in "${restricted_dirs[@]}"; do
        if [ -d "$wp_root/$dir" ]; then
            sudo chmod 2750 "$wp_root/$dir"
        fi
    done
    
    success "✓ Standardized permissions applied"
}

# Get the actual user's home directory (handles sudo correctly)
get_user_home() {
    # If running under sudo, get the original user's home
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        getent passwd "$SUDO_USER" | cut -d: -f6
    else
        echo "$HOME"
    fi
}

# Expand path with proper user home directory
expand_user_path() {
    local path="$1"
    local user_home=$(get_user_home)
    
    # Replace ~ or $HOME with actual user home
    path="${path/#\~/$user_home}"
    path="${path/#\$HOME/$user_home}"
    
    echo "$path"
}

# Verification to ensure WordPress is running
verify_wordpress_stack() {
    info "=== Final System Verification ==="
    
    local domain=$(load_state "DOMAIN")
    local wp_root=$(load_state "WP_ROOT")
    local wp_user=$(load_state "WP_USER")
    local php_version=$(load_state "PHP_VERSION")
    local all_good=true
    local issues=()
    
    # Check 1: PHP-FPM service running
    echo -n "Checking PHP-FPM service... "
    if sudo systemctl is-active --quiet "php${php_version}-fpm"; then
        echo -e "\033[0;32m✓\033[0m"
    else
        echo -e "\033[0;31m✗\033[0m"
        issues+=("PHP-FPM service not running")
        all_good=false
    fi
    
    # Check 2: PHP-FPM socket exists and has correct permissions
    echo -n "Checking PHP-FPM socket... "
    local php_socket=$(load_state "PHP_FPM_SOCKET")
    if [ -S "$php_socket" ]; then
        local socket_perms=$(stat -c "%U:%G %a" "$php_socket")
        if [[ "$socket_perms" =~ www-data:www-data.*660 ]]; then
            echo -e "\033[0;32m✓\033[0m"
        else
            echo -e "\033[1;33m⚠\033[0m (permissions: $socket_perms)"
            issues+=("PHP-FPM socket permissions suboptimal")
        fi
    else
        echo -e "\033[0;31m✗\033[0m"
        issues+=("PHP-FPM socket missing: $php_socket")
        all_good=false
    fi
    
    # Check 3: Nginx service running
    echo -n "Checking Nginx service... "
    if sudo systemctl is-active --quiet nginx; then
        echo -e "\033[0;32m✓\033[0m"
    else
        echo -e "\033[0;31m✗\033[0m"
        issues+=("Nginx service not running")
        all_good=false
    fi
    
    # Check 4: Database connection
    echo -n "Checking database connection... "
    if sudo -u "$wp_user" wp --path="$wp_root" db check >/dev/null 2>&1; then
        echo -e "\033[0;32m✓\033[0m"
    else
        echo -e "\033[0;31m✗\033[0m"
        issues+=("Database connection failed")
        all_good=false
    fi
    
    # Check 5: WordPress core files
    echo -n "Checking WordPress core files... "
    if [ -f "$wp_root/wp-config.php" ] && [ -f "$wp_root/wp-login.php" ]; then
        local wp_config_perms=$(stat -c "%U:%G %a" "$wp_root/wp-config.php")
        if [[ "$wp_config_perms" =~ $wp_user:wordpress.*640 ]]; then
            echo -e "\033[0;32m✓\033[0m"
        else
            echo -e "\033[1;33m⚠\033[0m (wp-config.php permissions: $wp_config_perms)"
            issues+=("wp-config.php permissions need attention")
        fi
    else
        echo -e "\033[0;31m✗\033[0m"
        issues+=("WordPress core files missing")
        all_good=false
    fi
    
    # Check 6: HTTP Response (if domain resolves)
    echo -n "Checking HTTP response... "
    if curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "https://$domain" 2>/dev/null | grep -q "200"; then
        echo -e "\033[0;32m✓\033[0m"
    elif curl -sS -o /dev/null -w "%{http_code}" --max-time 5 --insecure "https://$domain" 2>/dev/null | grep -q "200"; then
        echo -e "\033[1;33m⚠\033[0m (SSL certificate issue)"
        issues+=("SSL certificate needs attention")
    else
        # Check if it's a DNS/network issue vs server issue
        if curl -sS -o /dev/null --max-time 5 "http://localhost" >/dev/null 2>&1; then
            echo -e "\033[1;33m⚠\033[0m (domain not resolving locally)"
            issues+=("Domain DNS not configured for local testing")
        else
            echo -e "\033[0;31m✗\033[0m"
            issues+=("HTTP request failed - check nginx configuration")
            all_good=false
        fi
    fi
    
    echo
    
    # Show results
    if $all_good && [ ${#issues[@]} -eq 0 ]; then
        success "✓ All systems operational"
        return 0
    elif $all_good; then
        warning "⚠ System working with minor issues:"
        for issue in "${issues[@]}"; do
            echo "    • $issue"
        done
        echo
        warning "WordPress should work, but consider addressing these issues"
        return 0
    else
        error "✗ Critical issues found:"
        for issue in "${issues[@]}"; do
            echo "    • $issue"
        done
        echo
        error "WordPress may not function properly. Address these issues first."
        return 1
    fi
}

# ===== PHP VERSION MANAGEMENT =====
update_php_version() {
    local new_version=$1
    local current_version=$(get_php_version)
    
    if [ -z "$new_version" ]; then
        error "Usage: update_php_version <version>"
        info "Example: update_php_version 8.4"
        return 1
    fi
    
    info "Updating PHP from $current_version to $new_version..."
    
    # Install new PHP version
    local packages=(
        "php${new_version}-fpm"
        "php${new_version}-mysql"
        "php${new_version}-xml"
        "php${new_version}-curl"
        "php${new_version}-mbstring"
        "php${new_version}-gd"
        "php${new_version}-zip"
    )
    
    if ! sudo apt-get install -y "${packages[@]}"; then
        error "Failed to install PHP $new_version"
        return 1
    fi
    
    # Update symlinks
    local wp_user=$(load_state "WP_USER")
    local pool_name="${wp_user}_pool"
    local old_socket="/run/php/php${current_version}-fpm-${pool_name}.sock"
    local new_socket="/run/php/php${new_version}-fpm-${pool_name}.sock"
    local generic_socket="/run/php/php-fpm-${pool_name}.sock"
    
    # Copy pool configuration to new version
    if [ -f "/etc/php/${current_version}/fpm/pool.d/${pool_name}.conf" ]; then
        sudo cp "/etc/php/${current_version}/fpm/pool.d/${pool_name}.conf" \
                "/etc/php/${new_version}/fpm/pool.d/${pool_name}.conf"
        
        # Update version-specific paths in pool config
        sudo sed -i "s/php${current_version}/php${new_version}/g" \
            "/etc/php/${new_version}/fpm/pool.d/${pool_name}.conf"
    fi
    
    # Start new PHP-FPM
    sudo systemctl enable "php${new_version}-fpm"
    sudo systemctl start "php${new_version}-fpm"
    
    # Wait for new socket
    local retries=0
    while [ ! -S "$new_socket" ] && [ $retries -lt 30 ]; do
        sleep 1
        retries=$((retries + 1))
    done
    
    if [ -S "$new_socket" ]; then
        # Update symlink
        sudo ln -sf "$new_socket" "$generic_socket"
        
        # Update state
        save_state "PHP_VERSION" "$new_version"
        
        # Restart nginx
        sudo systemctl restart nginx
        
        # Stop old PHP-FPM
        sudo systemctl stop "php${current_version}-fpm"
        sudo systemctl disable "php${current_version}-fpm"
        
        success "PHP updated from $current_version to $new_version"
        info "Symlink updated: $generic_socket -> $new_socket"
    else
        error "New PHP-FPM socket not created"
        return 1
    fi
}

debug "Utils module loaded successfully"
