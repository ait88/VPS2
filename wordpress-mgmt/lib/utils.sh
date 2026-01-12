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
    # Include upgrade-temp-backup subdirectories for plugin/theme updates
    local writable_dirs=(
        "wp-content/uploads"
        "wp-content/cache"
        "wp-content/upgrade"
        "wp-content/upgrade-temp-backup"
        "wp-content/upgrade-temp-backup/plugins"
        "wp-content/upgrade-temp-backup/themes"
        "wp-content/wflogs"
        "tmp"
    )

    # Create directories if they don't exist, then set permissions
    for dir in "${writable_dirs[@]}"; do
        if [ ! -d "$wp_root/$dir" ]; then
            sudo mkdir -p "$wp_root/$dir"
        fi
        # Set directory permissions
        sudo chown php-fpm:wordpress "$wp_root/$dir"
        sudo chmod 2775 "$wp_root/$dir"
        # Set recursive ownership and permissions on contents (for existing files)
        sudo chown -R php-fpm:wordpress "$wp_root/$dir"
        sudo find "$wp_root/$dir" -type f -exec chmod 664 {} \; 2>/dev/null || true
        sudo find "$wp_root/$dir" -type d -exec chmod 2775 {} \; 2>/dev/null || true
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

# ===== ANONYMIZED DEBUG REPORT =====
# Generates comprehensive system state for troubleshooting
# All sensitive data (domains, IPs, emails, passwords, keys) is anonymized

generate_debug_report() {
    local output_dir="$WP_MGMT_DIR"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local output_file="$output_dir/debug-${timestamp}.md"
    local temp_file="/tmp/debug-report-$$.md"

    info "Generating anonymized debug report..."

    # Collect sensitive values for anonymization
    local domain=$(load_state "DOMAIN" "")
    local admin_email=$(load_state "ADMIN_EMAIL" "")
    local wp_user=$(load_state "WP_USER" "wpuser")
    local db_name=$(load_state "DB_NAME" "")
    local db_user=$(load_state "DB_USER" "")
    local wp_root=$(load_state "WP_ROOT" "/var/www/wordpress")

    # Start building report
    cat > "$temp_file" << 'HEADER'
# WordPress VPS Debug Report

> **Generated:** TIMESTAMP_PLACEHOLDER
> **Script Version:** VERSION_PLACEHOLDER
>
> This report contains anonymized system information for troubleshooting.
> Sensitive data (domains, IPs, emails, passwords) has been redacted.

---

HEADER

    # Replace placeholders
    sed -i "s/TIMESTAMP_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S %Z')/" "$temp_file"
    sed -i "s/VERSION_PLACEHOLDER/$(load_state "SCRIPT_VERSION" "unknown")/" "$temp_file"

    # Section 1: System Information
    {
        echo "## 1. System Information"
        echo ""
        echo '```'
        echo "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'Unknown')"
        echo "Kernel: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Hostname: [HOSTNAME_REDACTED]"
        echo ""
        echo "Memory:"
        free -h | head -2
        echo ""
        echo "Disk Usage:"
        df -h / | tail -1 | awk '{print "  Root: " $3 " used / " $2 " total (" $5 " used)"}'
        if [ -d "$wp_root" ]; then
            du -sh "$wp_root" 2>/dev/null | awk '{print "  WordPress: " $1}'
        fi
        echo ""
        echo "CPU: $(grep -c processor /proc/cpuinfo) cores"
        echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 2: Service Status
    {
        echo "## 2. Service Status"
        echo ""
        echo "| Service | Status | Notes |"
        echo "|---------|--------|-------|"

        # Check each service
        for service in nginx mariadb mysql redis-server fail2ban ufw; do
            local status="not installed"
            local notes="-"

            if systemctl list-unit-files "${service}.service" &>/dev/null; then
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    status="✅ running"
                elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    status="⚠️ stopped (enabled)"
                else
                    status="❌ stopped"
                fi
            fi

            echo "| $service | $status | $notes |"
        done

        # PHP-FPM (version-specific)
        local php_version=$(get_php_version 2>/dev/null || echo "")
        if [ -n "$php_version" ]; then
            local php_status="not installed"
            if systemctl is-active --quiet "php${php_version}-fpm" 2>/dev/null; then
                php_status="✅ running"
            else
                php_status="❌ stopped"
            fi
            echo "| php${php_version}-fpm | $php_status | - |"
        fi

        echo ""
    } >> "$temp_file"

    # Section 3: PHP Information
    {
        echo "## 3. PHP Configuration"
        echo ""
        if command -v php &>/dev/null; then
            echo '```'
            echo "PHP Version: $(php -v | head -1)"
            echo ""
            echo "Key Modules:"
            php -m 2>/dev/null | grep -iE "mysql|redis|curl|gd|mbstring|xml|zip|imagick|intl|bcmath" | sort | sed 's/^/  - /'
            echo ""
            echo "Memory Limit: $(php -i 2>/dev/null | grep "memory_limit" | head -1 | awk '{print $NF}')"
            echo "Max Execution: $(php -i 2>/dev/null | grep "max_execution_time" | head -1 | awk '{print $NF}')s"
            echo "Upload Max: $(php -i 2>/dev/null | grep "upload_max_filesize" | head -1 | awk '{print $NF}')"
            echo '```'
        else
            echo "*PHP not found in PATH*"
        fi
        echo ""
    } >> "$temp_file"

    # Section 4: Nginx Configuration
    {
        echo "## 4. Nginx Configuration"
        echo ""
        echo '```'
        echo "Nginx Version: $(nginx -v 2>&1 | head -1)"
        echo ""
        echo "Sites Enabled:"
        local site_count=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
        echo "  - $site_count site(s) configured [names redacted]"
        echo ""
        echo "Config Test: $(sudo nginx -t 2>&1 | tail -1)"
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 5: WordPress Status
    {
        echo "## 5. WordPress Status"
        echo ""
        if [ -f "$wp_root/wp-config.php" ]; then
            echo '```'
            echo "WordPress Root: [WP_ROOT]"
            echo "wp-config.php: exists"

            # Get WP version if WP-CLI available
            if command -v wp &>/dev/null; then
                local wp_ver=$(sudo -u "$wp_user" wp --path="$wp_root" core version 2>/dev/null || echo "unknown")
                echo "WordPress Version: $wp_ver"

                echo ""
                echo "Plugins:"
                sudo -u "$wp_user" wp --path="$wp_root" plugin list --format=csv 2>/dev/null | tail -n +2 | while IFS=, read -r name status update version; do
                    echo "  - $name ($status, v$version)"
                done 2>/dev/null || echo "  (unable to list)"

                echo ""
                echo "Active Theme:"
                sudo -u "$wp_user" wp --path="$wp_root" theme list --status=active --format=csv 2>/dev/null | tail -n +2 | while IFS=, read -r name status update version; do
                    echo "  - $name (v$version)"
                done 2>/dev/null || echo "  (unable to determine)"
            else
                echo "WP-CLI: not available"
            fi
            echo '```'
        else
            echo "*wp-config.php not found at expected location*"
        fi
        echo ""
    } >> "$temp_file"

    # Section 6: State File (Anonymized)
    {
        echo "## 6. Configuration State (Anonymized)"
        echo ""
        echo '```'
        if [ -f "$STATE_FILE" ]; then
            # Read and anonymize state file
            while IFS='=' read -r key value || [ -n "$key" ]; do
                # Skip empty lines and comments
                [[ -z "$key" || "$key" =~ ^# ]] && continue

                # Anonymize sensitive values
                case "$key" in
                    *PASS*|*SECRET*|*KEY*|*TOKEN*)
                        echo "$key=[REDACTED]"
                        ;;
                    *EMAIL*)
                        echo "$key=[EMAIL_REDACTED]"
                        ;;
                    DOMAIN|INCLUDE_WWW)
                        echo "$key=[DOMAIN_REDACTED]"
                        ;;
                    *USER*|*OWNER*)
                        if [[ "$value" =~ ^(www-data|php-fpm|root|wordpress|redis|mysql)$ ]]; then
                            echo "$key=$value"
                        else
                            echo "$key=[USER_REDACTED]"
                        fi
                        ;;
                    DB_NAME)
                        echo "$key=[DB_NAME_REDACTED]"
                        ;;
                    *WHITELIST*|*_IPS)
                        # Redact IP addresses in whitelist values
                        local anon_value=$(echo "$value" | sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[IP_REDACTED]/g')
                        echo "$key=$anon_value"
                        ;;
                    WP_ROOT|BACKUP_*|*_DIR|*_PATH|*_FILE|CRON_FILE)
                        # Redact home directory and domain from paths
                        local anon_value="$value"
                        anon_value=$(echo "$anon_value" | sed 's|/home/[^/]*|/home/[USER]|g')
                        # Replace domain in paths if set (both original and sanitized versions)
                        if [ -n "$domain" ]; then
                            # Replace original domain (e.g., example.com)
                            anon_value=$(echo "$anon_value" | sed "s|$domain|[DOMAIN]|g")
                            # Replace sanitized domain (dots/dashes to underscores, e.g., example_com)
                            local domain_sanitized="${domain//[.-]/_}"
                            anon_value=$(echo "$anon_value" | sed "s|$domain_sanitized|[DOMAIN]|g")
                        fi
                        echo "$key=$anon_value"
                        ;;
                    *)
                        echo "$key=$value"
                        ;;
                esac
            done < "$STATE_FILE"
        else
            echo "(state file not found)"
        fi
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 7: Permission Audit
    {
        echo "## 7. Permission Audit"
        echo ""
        echo '```'
        if [ -d "$wp_root" ]; then
            echo "WordPress Root:"
            ls -la "$wp_root" 2>/dev/null | head -5 | tail -4

            echo ""
            echo "wp-config.php:"
            ls -la "$wp_root/wp-config.php" 2>/dev/null | awk '{print $1, $3, $4}' || echo "  (not found)"

            echo ""
            echo "wp-content/uploads:"
            ls -la "$wp_root/wp-content/" 2>/dev/null | grep uploads | awk '{print $1, $3, $4}' || echo "  (not found)"
        else
            echo "(WordPress root not found)"
        fi
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 8: Firewall Status
    {
        echo "## 8. Firewall Status"
        echo ""
        echo '```'
        if command -v ufw &>/dev/null; then
            sudo ufw status 2>/dev/null | head -20 | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/[IP_REDACTED]/g'
        else
            echo "UFW not installed"
        fi
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 9: Recent Logs (Anonymized)
    {
        echo "## 9. Recent Log Entries (Anonymized)"
        echo ""

        # Function to anonymize log content
        anonymize_log() {
            local content
            content=$(cat)
            # Replace IPs
            content=$(echo "$content" | sed -E 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[IP]/g')
            # Replace emails
            content=$(echo "$content" | sed -E 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[EMAIL]/g')
            # Replace URLs
            content=$(echo "$content" | sed -E 's|https?://[^[:space:]"]+|[URL]|g')
            # Replace domain in paths (e.g., /var/www/example.com/...)
            if [ -n "$domain" ]; then
                content=$(echo "$content" | sed "s|$domain|[DOMAIN]|g")
            fi
            # Replace any remaining paths that look like domain-based WordPress roots
            content=$(echo "$content" | sed -E 's|/var/www/[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|/var/www/[DOMAIN]|g')
            echo "$content"
        }

        echo "### Nginx Error Log"
        echo '```'
        if [ -f /var/log/nginx/error.log ]; then
            sudo tail -20 /var/log/nginx/error.log 2>/dev/null | anonymize_log || echo "(unable to read)"
        else
            echo "(not found)"
        fi
        echo '```'
        echo ""

        echo "### PHP-FPM Log"
        echo '```'
        local php_ver=$(get_php_version 2>/dev/null || echo "8.3")
        local php_log="/var/log/php/${php_ver}-fpm-${wp_user}_pool-error.log"
        if [ -f "$php_log" ]; then
            sudo tail -20 "$php_log" 2>/dev/null | anonymize_log || echo "(unable to read)"
        else
            # Try alternative locations
            local alt_log=$(ls /var/log/php*error*.log 2>/dev/null | head -1)
            if [ -n "$alt_log" ]; then
                sudo tail -20 "$alt_log" 2>/dev/null | anonymize_log || echo "(unable to read)"
            else
                echo "(not found)"
            fi
        fi
        echo '```'
        echo ""

        echo "### Fail2Ban Log"
        echo '```'
        if [ -f /var/log/fail2ban.log ]; then
            sudo tail -20 /var/log/fail2ban.log 2>/dev/null | anonymize_log || echo "(unable to read)"
        else
            echo "(not found)"
        fi
        echo '```'
        echo ""
    } >> "$temp_file"

    # Section 10: Quick Health Checks
    {
        echo "## 10. Quick Health Checks"
        echo ""
        echo "| Check | Result |"
        echo "|-------|--------|"

        # PHP-FPM socket
        local php_socket=$(load_state "PHP_FPM_SOCKET" "")
        if [ -S "$php_socket" ]; then
            echo "| PHP-FPM Socket | ✅ exists |"
        else
            echo "| PHP-FPM Socket | ❌ missing |"
        fi

        # Nginx config test
        if sudo nginx -t 2>&1 | grep -q "successful"; then
            echo "| Nginx Config | ✅ valid |"
        else
            echo "| Nginx Config | ❌ invalid |"
        fi

        # Database connection
        if command -v mysql &>/dev/null && mysql -e "SELECT 1" &>/dev/null; then
            echo "| Database | ✅ accessible |"
        else
            echo "| Database | ⚠️ check credentials |"
        fi

        # WordPress files
        if [ -f "$wp_root/wp-config.php" ] && [ -f "$wp_root/wp-login.php" ]; then
            echo "| WordPress Files | ✅ present |"
        else
            echo "| WordPress Files | ❌ missing |"
        fi

        # SSL certificate
        local ssl_type=$(load_state "SSL_TYPE" "none")
        echo "| SSL Type | $ssl_type |"

        # WAF type
        local waf_type=$(load_state "WAF_TYPE" "none")
        echo "| WAF Type | $waf_type |"

        echo ""
    } >> "$temp_file"

    # Footer
    {
        echo "---"
        echo ""
        echo "*Report generated by WordPress VPS Management System*"
        echo "*GitHub: https://github.com/ait88/VPS2*"
    } >> "$temp_file"

    # Save to output file
    cp "$temp_file" "$output_file"
    rm -f "$temp_file"

    # Display report
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$output_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    success "Debug report saved to: $output_file"
    info "You can copy the above output or attach the file when reporting issues."
}

debug "Utils module loaded successfully"
