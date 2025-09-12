#!/bin/bash
# wordpress-mgmt/lib/config.sh - Interactive configuration gathering
# Version: 3.0.0

# Color definitions for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

configure_interactive() {
    info "=== WordPress Configuration ==="
    
    if state_exists "CONFIG_COMPLETED"; then
        if confirm "Configuration already exists. Reconfigure?" N; then
            info "Reconfiguring..."
        else
            info "✓ Using existing configuration"
            return 0
        fi
    fi
    
    # Load existing values for defaults
    local current_domain=$(load_state "DOMAIN")
    local current_wp_root=$(load_state "WP_ROOT" "/var/www/wordpress")
    
    # Site Configuration
    echo
    info "Site Configuration"
    echo "────────────────────"
    
    # Domain configuration
    while true; do
        get_input "Primary domain (e.g., example.com)" "$current_domain"
        local domain="$INPUT_RESULT"
        
        if validate_domain "$domain"; then
            save_state "DOMAIN" "$domain"
            break
        else
            error "Invalid domain format. Please try again."
        fi
    done
    
    # WWW subdomain
    if confirm "Include www.$domain as an alias?" Y; then
        save_state "INCLUDE_WWW" "true"
    else
        save_state "INCLUDE_WWW" "false"
    fi
    
    # WordPress root directory
    get_input "WordPress root directory" "$current_wp_root"
    save_state "WP_ROOT" "$INPUT_RESULT"
    
    # Admin email
    local default_email="admin@$domain"
    get_input "Administrator email" "$default_email"
    local admin_email="$INPUT_RESULT"
    if validate_email "$admin_email"; then
        save_state "ADMIN_EMAIL" "$admin_email"
    else
        warning "Invalid email format, using default"
        save_state "ADMIN_EMAIL" "$default_email"
    fi
    
    # Database Configuration
    echo
    info "Database Configuration"
    echo "────────────────────"
    
    # Database name (sanitized from domain)
    local default_db="wp_${domain//[.-]/_}"
    get_input "Database name" "$default_db"
    save_state "DB_NAME" "$INPUT_RESULT"
    
    # Database user
    local default_db_user="${INPUT_RESULT}_user"
    get_input "Database user" "$default_db_user"
    save_state "DB_USER" "$INPUT_RESULT"
    
    # Generate secure password
    local db_pass=$(generate_password 24)
    save_state "DB_PASS" "$db_pass"
    echo -e "Database password (generated): ${GREEN}$db_pass${NC}"
    echo -e "${YELLOW}⚠ Save this password - it won't be shown again${NC}"
    
    # Security Configuration
    echo
    info "Security Configuration"
    echo "────────────────────"
    
    # WAF/Proxy configuration
    configure_waf_proxy
    
    # Redis Cache
    if confirm "Enable Redis object cache?" Y; then
        save_state "ENABLE_REDIS" "true"
        
        # Redis password
        local redis_pass=$(generate_password 32)
        save_state "REDIS_PASS" "$redis_pass"
        info "Redis password generated and saved"
    else
        save_state "ENABLE_REDIS" "false"
    fi
    
    # SSL Configuration
    echo
    info "SSL Configuration"
    echo "────────────────────"
    
    PS3="Select SSL configuration: "
    local ssl_options=(
        "Cloudflare Origin Certificate (Recommended for CF proxy)"
        "Let's Encrypt (Direct access only)"
        "Self-signed (Development)"
        "Manual (I'll configure later)"
        "None (HTTP only)"
    )
    
    select ssl_opt in "${ssl_options[@]}"; do
        case $REPLY in
            1) save_state "SSL_TYPE" "cloudflare_origin"; break ;;
            2) save_state "SSL_TYPE" "letsencrypt"; break ;;
            3) save_state "SSL_TYPE" "selfsigned"; break ;;
            4) save_state "SSL_TYPE" "manual"; break ;;
            5) save_state "SSL_TYPE" "none"; break ;;
        esac
    done
    
    # Performance Configuration
    echo
    info "Performance Configuration"
    echo "────────────────────"
    
    # Detect system resources
    eval "$(get_system_info)"
    
    # PHP memory limit based on available RAM
    local php_memory="256M"
    if [ "$TOTAL_MEM" -ge 2048 ]; then
        php_memory="512M"
    elif [ "$TOTAL_MEM" -ge 4096 ]; then
        php_memory="1024M"
    fi
    
    get_input "PHP memory limit" "$php_memory"
    save_state "PHP_MEMORY_LIMIT" "$INPUT_RESULT"
    
    # PHP workers based on CPU cores
    local php_workers=$((CPU_CORES * 2))
    get_input "PHP-FPM workers" "$php_workers"
    save_state "PHP_WORKERS" "$INPUT_RESULT"
    
    # Installation Options
    echo
    info "Installation Options"
    echo "────────────────────"
    
    # WordPress version
    PS3="Select WordPress version: "
    local wp_versions=(
        "Latest stable"
        "Specific version"
        "Skip WordPress installation"
    )
    
    select wp_ver in "${wp_versions[@]}"; do
        case $REPLY in
            1) 
                save_state "WP_VERSION" "latest"
                break 
                ;;
            2) 
                get_input "WordPress version (e.g., 6.4.2)" ""
                save_state "WP_VERSION" "$INPUT_RESULT"
                break 
                ;;
            3) 
                save_state "WP_VERSION" "skip"
                break 
                ;;
        esac
    done
    
    # Default plugins
    if [ "$(load_state "WP_VERSION")" != "skip" ]; then
        info "Select default plugins to install:"
        
        local plugins=(
            "wordfence:Security plugin"
            "redis-cache:Redis object cache"
            "wp-mail-smtp:Email configuration"
            "updraftplus:Backup plugin"
            "wordpress-seo:Yoast SEO"
        )
        
        local selected_plugins=()
        for plugin_info in "${plugins[@]}"; do
            local plugin="${plugin_info%%:*}"
            local desc="${plugin_info#*:}"
            
            if confirm "Install $desc?" Y; then
                selected_plugins+=("$plugin")
            fi
        done
        
        save_state "WP_PLUGINS" "${selected_plugins[*]}"
    fi
    
    # Save configuration timestamp
    save_state "CONFIG_COMPLETED" "$(date +%Y-%m-%d_%H:%M:%S)"
    
    # Display summary
    show_configuration_summary
    
    if ! confirm "Proceed with this configuration?" Y; then
        error "Configuration cancelled"
        exit 1
    fi
    
    success "✓ Configuration saved successfully"
}

configure_waf_proxy() {
    PS3="Select WAF/Proxy configuration: "
    local waf_options=(
        "None - Direct Internet access"
        "Cloudflare Free/Pro"
        "Cloudflare Enterprise"
        "Sucuri WAF"
        "BunkerWeb"
        "Custom WAF/Proxy"
    )
    
    select waf in "${waf_options[@]}"; do
        case $REPLY in
            1)
                save_state "WAF_TYPE" "none"
                info "Direct Internet access selected"
                break
                ;;
            2)
                save_state "WAF_TYPE" "cloudflare"
                configure_cloudflare_ips
                break
                ;;
            3)
                save_state "WAF_TYPE" "cloudflare_ent"
                info "Enter Cloudflare Enterprise IP ranges:"
                configure_custom_waf_ips
                break
                ;;
            4)
                save_state "WAF_TYPE" "sucuri"
                configure_sucuri_ips
                break
                ;;
            5)
                save_state "WAF_TYPE" "bunkerweb"
                configure_bunkerweb
                break
                ;;
            6)
                save_state "WAF_TYPE" "custom"
                configure_custom_waf_ips
                break
                ;;
        esac
    done
}

configure_cloudflare_ips() {
    info "Cloudflare IPs will be automatically fetched during setup"
    save_state "WAF_AUTO_UPDATE_IPS" "true"
    
    # Real IP header
    save_state "REAL_IP_HEADER" "CF-Connecting-IP"
    
    # Ask about authenticated origin pulls
    if confirm "Enable Cloudflare Authenticated Origin Pulls?" Y; then
        save_state "CF_AUTH_ORIGIN_PULLS" "true"
    fi
}

configure_sucuri_ips() {
    # Sucuri WAF IP ranges
    local sucuri_ips=(
        "192.88.134.0/23"
        "185.93.228.0/22"
        "66.248.200.0/22"
        "208.109.0.0/22"
        "2a02:fe80::/29"
    )
    
    save_state "WAF_IPS" "${sucuri_ips[*]}"
    save_state "REAL_IP_HEADER" "X-Sucuri-ClientIP"
    info "Sucuri WAF IPs configured"
}

configure_bunkerweb() {
    get_input "BunkerWeb IP address or range" ""
    save_state "WAF_IPS" "$INPUT_RESULT"
    save_state "REAL_IP_HEADER" "X-Forwarded-For"
    
    if confirm "Is BunkerWeb running in Docker on this host?" N; then
        save_state "BUNKERWEB_LOCAL" "true"
    fi
}

configure_custom_waf_ips() {
    local waf_ips=()
    
    info "Enter WAF/Proxy IP addresses (one per line, empty line to finish):"
    while true; do
        read -p "IP/CIDR: " ip
        [ -z "$ip" ] && break
        
        # Basic validation
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
            waf_ips+=("$ip")
            echo "Added: $ip"
        else
            warning "Invalid IP format: $ip"
        fi
    done
    
    if [ ${#waf_ips[@]} -eq 0 ]; then
        warning "No IPs entered, WAF configuration skipped"
        save_state "WAF_TYPE" "none"
    else
        save_state "WAF_IPS" "${waf_ips[*]}"
        
        # Real IP header
        get_input "Real IP header name" "X-Forwarded-For"
        save_state "REAL_IP_HEADER" "$INPUT_RESULT"
    fi
}

show_configuration_summary() {
    echo
    info "=== Configuration Summary ==="
    echo "────────────────────────────"
    
    cat <<EOF
Domain: $(load_state "DOMAIN")
WWW Alias: $(load_state "INCLUDE_WWW")
WordPress Root: $(load_state "WP_ROOT")
Admin Email: $(load_state "ADMIN_EMAIL")

Database: $(load_state "DB_NAME")
DB User: $(load_state "DB_USER")

WAF Type: $(load_state "WAF_TYPE")
SSL Type: $(load_state "SSL_TYPE")
Redis Cache: $(load_state "ENABLE_REDIS")

PHP Memory: $(load_state "PHP_MEMORY_LIMIT")
PHP Workers: $(load_state "PHP_WORKERS")

WordPress: $(load_state "WP_VERSION")
EOF
    
    local plugins=$(load_state "WP_PLUGINS")
    if [ -n "$plugins" ]; then
        echo "Plugins: $plugins"
    fi
    
    echo "────────────────────────────"
}

# Helper function for input with result in INPUT_RESULT
get_input() {
    local prompt=$1
    local default=$2
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " INPUT_RESULT
        INPUT_RESULT="${INPUT_RESULT:-$default}"
    else
        read -p "$prompt: " INPUT_RESULT
    fi
}

debug "Config module loaded successfully"
