#!/bin/bash
# wordpress-mgmt/lib/packages.sh - Package installation and management
# Version: 3.0.0

install_packages() {
    info "Installing required packages..."
    
    # Skip if already completed
    if state_exists "PACKAGES_INSTALLED"; then
        info "✓ Packages already installed"
        return 0
    fi
    
    # Update package lists
    show_progress 1 8 "Updating package lists"
    sudo apt-get update -qq || {
        error "Failed to update package lists"
        exit 1
    }
    
    # Detect best PHP version available
    show_progress 2 8 "Detecting PHP version"
    local php_version=$(detect_php_version)
    info "Selected PHP version: $php_version"
    save_state "PHP_VERSION" "$php_version"
    
    # Core packages array
    local packages=(
        # Web server
        nginx
        nginx-extras
        
        # Database
        mariadb-server
        mariadb-client
        
        # PHP and extensions
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
        "php${php_version}-soap"
        "php${php_version}-opcache"
        "php${php_version}-cli"
        
        # Security
        fail2ban
        certbot
        python3-certbot-nginx
        ufw
        
        # Tools
        curl
        wget
        unzip
        rsync
        git
        htop
        iotop
        ncdu
        
        # Build tools (for some WP plugins)
        build-essential
        software-properties-common
    )
    
    # Install packages
    show_progress 3 8 "Installing packages (this may take a while)"
    local failed_packages=()
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            debug "Installing $package..."
            if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" &>/dev/null; then
                failed_packages+=("$package")
            fi
        fi
    done
    
    # Report any failures
    if [ ${#failed_packages[@]} -gt 0 ]; then
        warning "Some packages failed to install: ${failed_packages[*]}"
        warning "This may not be critical, continuing..."
    fi
    
    # Install WP-CLI
    show_progress 4 8 "Installing WP-CLI"
    install_wp_cli
    
    # Configure PHP
    show_progress 5 8 "Configuring PHP defaults"
    configure_php_defaults "$php_version"
    
    # Start and enable services
    show_progress 6 8 "Enabling services"
    enable_services "$php_version"
    
    # Install additional tools
    show_progress 7 8 "Installing additional tools"
    install_additional_tools
    
    # Verify installation
    show_progress 8 8 "Verifying installation"
    verify_installation "$php_version"
    
    save_state "PACKAGES_INSTALLED" "true"
    success "✓ All packages installed successfully"
}

detect_php_version() {
    # Check if PHP is already installed
    if command -v php &>/dev/null; then
        php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'
        return
    fi
    
    # Otherwise, find the latest available version
    local available_versions=$(apt-cache search --names-only '^php[0-9]+\.[0-9]+-fpm$' | 
                               grep -oP 'php\K[0-9]+\.[0-9]+' | 
                               sort -V | 
                               tail -1)
    
    # Default to 8.2 if detection fails
    echo "${available_versions:-8.2}"
}

install_wp_cli() {
    if command -v wp &>/dev/null; then
        debug "WP-CLI already installed"
        return 0
    fi
    
    local wp_cli_url="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    local wp_cli_path="/usr/local/bin/wp"
    
    # Download WP-CLI
    if curl -fsSL "$wp_cli_url" -o /tmp/wp-cli.phar; then
        chmod +x /tmp/wp-cli.phar
        sudo mv /tmp/wp-cli.phar "$wp_cli_path"
        
        # Verify installation
        if wp --info &>/dev/null; then
            debug "WP-CLI installed successfully"
        else
            warning "WP-CLI installed but verification failed"
        fi
    else
        warning "Failed to download WP-CLI"
    fi
}

configure_php_defaults() {
    local php_version=$1
    local php_ini="/etc/php/${php_version}/fpm/php.ini"
    
    if [ ! -f "$php_ini" ]; then
        warning "PHP configuration file not found: $php_ini"
        return 1
    fi
    
    # Backup original
    backup_file "$php_ini"
    
    # Update PHP settings for WordPress
    local settings=(
        "upload_max_filesize = 64M"
        "post_max_size = 64M"
        "memory_limit = 256M"
        "max_execution_time = 300"
        "max_input_time = 300"
        "max_input_vars = 3000"
    )
    
    for setting in "${settings[@]}"; do
        local key=$(echo "$setting" | cut -d'=' -f1 | xargs)
        local value=$(echo "$setting" | cut -d'=' -f2 | xargs)
        
        # Update or add setting
        if grep -q "^${key} = " "$php_ini"; then
            sudo sed -i "s/^${key} = .*/${setting}/" "$php_ini"
        else
            echo "$setting" | sudo tee -a "$php_ini" >/dev/null
        fi
    done
    
    debug "PHP defaults configured"
}

enable_services() {
    local php_version=$1
    local services=(
        "nginx"
        "php${php_version}-fpm"
        "mariadb"
        "fail2ban"
    )
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            sudo systemctl enable "$service" &>/dev/null || true
            
            # Start if not running
            if ! sudo systemctl is-active --quiet "$service"; then
                sudo systemctl start "$service" || {
                    warning "Failed to start $service"
                }
            fi
        else
            debug "Service not found: $service"
        fi
    done
}

install_additional_tools() {
    # Install Composer (useful for some plugins)
    if ! command -v composer &>/dev/null; then
        debug "Installing Composer..."
        curl -sS https://getcomposer.org/installer | php -- --quiet
        sudo mv composer.phar /usr/local/bin/composer 2>/dev/null || true
    fi
    
    # Install nodejs/npm (for modern WordPress development)
    if ! command -v node &>/dev/null && confirm "Install Node.js for modern WordPress development?" N; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
}

verify_installation() {
    local php_version=$1
    local all_good=true
    
    # Check critical services
    local services=(
        "nginx"
        "php${php_version}-fpm" 
        "mariadb"
    )
    
    for service in "${services[@]}"; do
        if ! sudo systemctl is-active --quiet "$service"; then
            error "Service not running: $service"
            all_good=false
        fi
    done
    
    # Check critical commands
    local commands=(
        "nginx"
        "php"
        "mysql"
        "wp"
    )
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Command not found: $cmd"
            all_good=false
        fi
    done
    
    # Check PHP modules
    local required_modules=(
        "mysql"
        "gd"
        "mbstring"
        "xml"
        "curl"
    )
    
    for module in "${required_modules[@]}"; do
        if ! php -m | grep -qi "^${module}$"; then
            warning "PHP module not loaded: $module"
        fi
    done
    
    if ! $all_good; then
        error "Package verification failed"
        return 1
    fi
    
    debug "All packages verified successfully"
}

# Function to uninstall packages (for cleanup/reset)
uninstall_packages() {
    if ! confirm "Remove all WordPress-related packages? This cannot be undone!" N; then
        return 1
    fi
    
    info "Removing packages..."
    
    # Stop services first
    local services=(
        "nginx"
        "php*-fpm"
        "mariadb"
    )
    
    for service in "${services[@]}"; do
        sudo systemctl stop $service 2>/dev/null || true
    done
    
    # Remove packages
    sudo apt-get remove --purge -y nginx* php* mariadb* mysql*
    sudo apt-get autoremove -y
    
    # Remove WP-CLI
    sudo rm -f /usr/local/bin/wp
    
    # Clear state
    state_exists "PACKAGES_INSTALLED" && save_state "PACKAGES_INSTALLED" "false"
    
    warning "Packages removed. You may need to manually clean up configuration files in /etc/"
}

debug "Packages module loaded successfully"