#!/bin/bash
# wordpress-mgmt/lib/preflight.sh - System preflight checks
# Version: 3.0.0

run_preflight_checks() {
    info "Running system preflight checks..."
    
    # Skip if already completed
    if state_exists "PREFLIGHT_COMPLETED"; then
        info "✓ Preflight checks already completed"
        return 0
    fi
    
    local checks_passed=0
    local total_checks=7
    
    # Check 1: Sudo access
    show_progress 1 $total_checks "Checking sudo access"
    check_sudo
    
    # Check 2: Operating system
    show_progress 2 $total_checks "Checking operating system"
    check_os
    
    # Check 3: Disk space (minimum 2GB free)
    show_progress 3 $total_checks "Checking disk space"
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2097152 ]; then
        error "Insufficient disk space. Need 2GB, have $(df -h / | awk 'NR==2 {print $4}')"
        exit 1
    fi
    
    # Check 4: Memory (warn if less than 512MB)
    show_progress 4 $total_checks "Checking memory"
    local total_mem=$(free -m | awk 'NR==2 {print $2}')
    if [ "$total_mem" -lt 512 ]; then
        warning "Low memory detected: ${total_mem}MB (recommended: 1GB+)"
    fi
    
    # Check 5: Network connectivity
    show_progress 5 $total_checks "Checking network connectivity"
    check_connectivity
    
    # Check 6: Check for conflicting services
    show_progress 6 $total_checks "Checking for conflicts"
    check_conflicting_services
    
    # Check 7: Required commands
    show_progress 7 $total_checks "Checking required commands"
    check_required_commands
    
    save_state "PREFLIGHT_COMPLETED" "true"
    save_state "PREFLIGHT_DATE" "$(date +%Y-%m-%d)"
    
    success "✓ All preflight checks passed"
}

check_conflicting_services() {
    local conflicts=()
    
    # Check for conflicting web servers
    for service in apache2 lighttpd; do
        if sudo systemctl is-active --quiet $service 2>/dev/null; then
            conflicts+=("$service")
        fi
    done
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        warning "Conflicting services detected: ${conflicts[*]}"
        
        for service in "${conflicts[@]}"; do
            if confirm "Stop and disable $service?"; then
                sudo systemctl stop $service
                sudo systemctl disable $service
                success "$service stopped and disabled"
            else
                error "Cannot continue with $service running"
                exit 1
            fi
        done
    fi
}

check_required_commands() {
    local required_commands=(
        "curl"
        "wget" 
        "openssl"
        "systemctl"
        "mysql"
    )
    
    local missing_commands=()
    local missing_services=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    # Check for MariaDB server service
    if ! sudo systemctl status mariadb &>/dev/null; then
        if ! dpkg -l | grep -q mariadb-server; then
            missing_services+=("mariadb-server")
        fi
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ] || [ ${#missing_services[@]} -gt 0 ]; then
        if [ ${#missing_commands[@]} -gt 0 ]; then
            warning "Missing required commands: ${missing_commands[*]}"
        fi
        if [ ${#missing_services[@]} -gt 0 ]; then
            warning "Missing required services: ${missing_services[*]}"
        fi
        
        if confirm "Install missing packages?"; then
            local packages=""
            for cmd in "${missing_commands[@]}"; do
                case $cmd in
                    curl) packages="$packages curl" ;;
                    wget) packages="$packages wget" ;;
                    openssl) packages="$packages openssl" ;;
                    mysql) packages="$packages mariadb-client" ;;
                esac
            done
            
            # Add MariaDB server if missing
            for service in "${missing_services[@]}"; do
                case $service in
                    mariadb-server) packages="$packages mariadb-server mariadb-client" ;;
                esac
            done
            
            if [ -n "$packages" ]; then
                info "Installing packages:$packages"
                sudo apt-get update -qq
                sudo apt-get install -y $packages
                
                # Start and enable MariaDB if it was installed
                if [[ "$packages" =~ mariadb-server ]]; then
                    info "Starting MariaDB service..."
                    sudo systemctl start mariadb
                    sudo systemctl enable mariadb
                    
                    # Wait for MariaDB to be ready
                    local timeout=30
                    local count=0
                    while ! sudo mysqladmin ping --silent && [ $count -lt $timeout ]; do
                        sleep 1
                        count=$((count + 1))
                    done
                    
                    if [ $count -eq $timeout ]; then
                        error "MariaDB failed to start after installation"
                        exit 1
                    else
                        success "✓ MariaDB installed and started"
                    fi
                fi
            fi
        else
            error "Required packages missing"
            exit 1
        fi
    fi
}

check_existing_wordpress() {
    info "Scanning for existing WordPress installations..."
    
    local wp_found=false
    local wp_locations=()
    
    # Common WordPress locations
    local search_paths=(
        "/var/www"
        "/home/*/public_html"
        "/opt"
    )
    
    for path in "${search_paths[@]}"; do
        # Find wp-config.php files
        while IFS= read -r -d '' wp_config; do
            wp_found=true
            wp_dir=$(dirname "$wp_config")
            wp_locations+=("$wp_dir")
            
            # Get WordPress version if possible
            local wp_version="Unknown"
            local version_file="$wp_dir/wp-includes/version.php"
            if [ -f "$version_file" ]; then
                wp_version=$(grep "wp_version =" "$version_file" | head -1 | cut -d"'" -f2)
            fi
            
            info "Found WordPress $wp_version at: $wp_dir"
            
        done < <(find $path -name "wp-config.php" -type f -print0 2>/dev/null)
    done
    
    if $wp_found; then
        save_state "EXISTING_WP_FOUND" "true"
        save_state "EXISTING_WP_PATHS" "$(IFS=:; echo "${wp_locations[*]}")"
        
        warning "Found existing WordPress installation(s)"
        warning "Continuing will create a new installation"
        
        if ! confirm "Continue anyway?"; then
            info "Installation cancelled"
            exit 0
        fi
    else
        info "✓ No existing WordPress installations found"
        save_state "EXISTING_WP_FOUND" "false"
    fi
}

check_system_resources() {
    info "Analyzing system resources..."
    
    # Get system information
    eval "$(get_system_info)"
    
    # CPU cores check
    if [ "$CPU_CORES" -eq 1 ]; then
        warning "Single CPU core detected - performance may be limited"
    else
        info "✓ CPU cores: $CPU_CORES"
    fi
    
    # Memory recommendations
    if [ "$TOTAL_MEM" -lt 1024 ]; then
        warning "Memory: ${TOTAL_MEM}MB (recommended: 1GB+)"
        
        # Suggest swap if very low memory
        if [ "$TOTAL_MEM" -lt 512 ]; then
            if confirm "Create swap file to improve performance?"; then
                create_swap_file
            fi
        fi
    else
        info "✓ Memory: ${TOTAL_MEM}MB"
    fi
    
    # Disk space breakdown
    info "✓ Available disk space: $(df -h / | awk 'NR==2 {print $4}')"
    
    # Save system info to state
    save_state "SYSTEM_MEM" "$TOTAL_MEM"
    save_state "SYSTEM_CORES" "$CPU_CORES"
    save_state "SYSTEM_DISK" "$AVAILABLE_SPACE"
}

create_swap_file() {
    local swap_size="1G"
    local swap_file="/swapfile"
    
    if [ -f "$swap_file" ]; then
        info "Swap file already exists"
        return 0
    fi
    
    info "Creating ${swap_size} swap file..."
    
    sudo fallocate -l "$swap_size" "$swap_file"
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file"
    sudo swapon "$swap_file"
    
    # Make permanent
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
    
    success "Swap file created and activated"
}

debug "Preflight module loaded successfully"