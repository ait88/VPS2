#!/bin/bash
# wordpress-mgmt/lib/security.sh - Security hardening and fail2ban
# Version: 3.0.0

apply_security() {
    info "Applying security hardening..."
    
    if state_exists "SECURITY_CONFIGURED"; then
        info "✓ Security already configured"
        return 0
    fi
    
    # Security steps
    show_progress 1 6 "Configuring Fail2ban"
    setup_fail2ban
    
    show_progress 2 6 "Setting up firewall rules"
    configure_ufw
    
    show_progress 3 6 "Hardening file permissions"
    harden_permissions
    
    show_progress 4 6 "Configuring system security"
    apply_system_hardening
    
    show_progress 5 6 "Setting up intrusion detection"
    setup_monitoring
    
    show_progress 6 6 "Creating security report"
    generate_security_report
    
    save_state "SECURITY_CONFIGURED" "true"
    success "✓ Security hardening applied"
}

setup_fail2ban() {
    info "Configuring Fail2ban for WordPress..."
    
    # Create WordPress filter
    sudo tee /etc/fail2ban/filter.d/wordpress.conf >/dev/null <<'EOF'
[Definition]
failregex = ^<HOST> .* "POST /wp-login\.php
            ^<HOST> .* "POST /xmlrpc\.php
            ^<HOST> .* "GET /author/
            ^<HOST> .* "GET .*(?:author=\d+)
            ^<HOST> .* "POST /wp-admin/admin-ajax\.php
            Authentication failure for .* from <HOST>$
            Blocked user enumeration attempt from <HOST>$
            Blocked authentication attempt for .* from <HOST>$

ignoreregex =
EOF
    
    # Create WordPress jail
    local domain=$(load_state "DOMAIN")
    local waf_type=$(load_state "WAF_TYPE" "none")
    
    sudo tee /etc/fail2ban/jail.d/wordpress.conf >/dev/null <<EOF
[wordpress-auth]
enabled = true
filter = wordpress
port = http,https
logpath = /var/log/nginx/${domain}_access.log
          /var/log/nginx/${domain}_error.log
maxretry = 5
findtime = 600
bantime = 3600
$([ "$waf_type" != "none" ] && echo "# WAF mode - be careful with IP banning")

[wordpress-xmlrpc]
enabled = true
filter = wordpress
port = http,https
logpath = /var/log/nginx/${domain}_access.log
maxretry = 3
findtime = 300
bantime = 86400

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/${domain}_access.log
maxretry = 6
findtime = 60
bantime = 3600

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/${domain}_access.log
maxretry = 2
findtime = 3600
bantime = 86400

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/${domain}_access.log
maxretry = 2
findtime = 60
bantime = 86400
EOF
    
    # Custom action for WAF environments
    if [ "$waf_type" != "none" ]; then
        sudo tee /etc/fail2ban/action.d/wordpress-waf.conf >/dev/null <<'EOF'
[Definition]
actionstart = 
actionstop = 
actioncheck = 
actionban = echo "Ban request for <ip> - WAF should handle this" >> /var/log/fail2ban-waf.log
actionunban = echo "Unban request for <ip>" >> /var/log/fail2ban-waf.log
EOF
        
        # Update jail to use custom action
        sudo sed -i '/\[wordpress-auth\]/a action = wordpress-waf' /etc/fail2ban/jail.d/wordpress.conf
    fi
    
    # Restart fail2ban
    restart_service "fail2ban"
}

configure_ufw() {
    info "Configuring firewall rules..."
    
    local waf_type=$(load_state "WAF_TYPE" "none")
    local domain=$(load_state "DOMAIN")
    
    # Basic rules
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # SSH (already configured by vps-setup.sh)
    # Keep existing SSH rules
    
    # Web traffic based on WAF
    if [ "$waf_type" = "none" ]; then
        # Direct access
        sudo ufw allow 80/tcp comment "HTTP"
        sudo ufw allow 443/tcp comment "HTTPS"
    else
        # WAF restricted access
        local waf_ips=$(load_state "WAF_IPS")
        
        if [ "$waf_type" = "cloudflare" ] || [ "$waf_type" = "cloudflare_ent" ]; then
            # Fetch and allow Cloudflare IPs
            info "Adding Cloudflare IP ranges to firewall..."
            
            # IPv4
            curl -s https://www.cloudflare.com/ips-v4 | while read ip; do
                sudo ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare"
            done
            
            # IPv6
            curl -s https://www.cloudflare.com/ips-v6 | while read ip; do
                sudo ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare"
            done
        else
            # Custom WAF IPs
            for ip in $waf_ips; do
                sudo ufw allow from "$ip" to any port 80,443 proto tcp comment "WAF"
            done
        fi
        
        # Monitoring exception
        local monitor_ip=$(load_state "MONITOR_IP")
        if [ -n "$monitor_ip" ]; then
            sudo ufw allow from "$monitor_ip" to any port 80,443 proto tcp comment "Monitoring"
        fi
    fi
    
    # Database (local only)
    sudo ufw allow from 127.0.0.1 to any port 3306 comment "MariaDB local"
    
    # Redis (if enabled)
    if [ "$(load_state "ENABLE_REDIS")" = "true" ]; then
        sudo ufw allow from 127.0.0.1 to any port 6379 comment "Redis local"
    fi
    
    # Enable firewall
    sudo ufw --force enable
    
    success "Firewall configured"
}

harden_permissions() {
    info "Hardening file permissions..."
    
    local wp_root=$(load_state "WP_ROOT")
    local wp_user=$(load_state "WP_USER")
    local php_user=$(load_state "PHP_USER")
    
    # Remove unnecessary permissions
    sudo find "$wp_root" -type f -name "*.php" -exec chmod 640 {} \;
    sudo find "$wp_root" -type d -exec chmod 750 {} \;
    
    # Protect sensitive files
    local sensitive_files=(
        "wp-config.php"
        ".htaccess"
        "nginx.conf"
        "php.ini"
        ".user.ini"
    )
    
    for file in "${sensitive_files[@]}"; do
        [ -f "$wp_root/$file" ] && sudo chmod 400 "$wp_root/$file"
    done
    
    # Remove unnecessary files
    local remove_files=(
        "readme.html"
        "license.txt"
        "wp-config-sample.php"
        "wp-admin/install.php"
        "wp-admin/upgrade.php"
    )
    
    for file in "${remove_files[@]}"; do
        [ -f "$wp_root/$file" ] && sudo rm -f "$wp_root/$file"
    done
    
    # Set immutable flag on critical files
    if confirm "Make wp-config.php immutable? (prevents modifications)" Y; then
        sudo chattr +i "$wp_root/wp-config.php"
        info "wp-config.php is now immutable (use 'chattr -i' to modify)"
    fi
}

apply_system_hardening() {
    info "Applying system-level hardening..."
    
    # Kernel parameters
    sudo tee /etc/sysctl.d/99-wordpress-security.conf >/dev/null <<'EOF'
# WordPress Security Hardening
# Network security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# File system hardening
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-wordpress-security.conf >/dev/null
    
    # Disable unnecessary services
    local disable_services=(
        "bluetooth"
        "cups"
        "avahi-daemon"
    )
    
    for service in "${disable_services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            sudo systemctl disable "$service" 2>/dev/null || true
            sudo systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    # Configure login banners
    echo "Authorized access only. All activity is monitored and logged." | sudo tee /etc/issue.net >/dev/null
}

setup_monitoring() {
    info "Setting up security monitoring..."
    
    # Install and configure aide (if not present)
    if ! command -v aide &>/dev/null; then
        if confirm "Install AIDE for file integrity monitoring?" Y; then
            sudo apt-get install -y aide
            sudo aideinit
            sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
            
            # Create weekly check
            sudo tee /etc/cron.weekly/aide-check >/dev/null <<'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Report for $(hostname)" root
EOF
            sudo chmod +x /etc/cron.weekly/aide-check
        fi
    fi
    
    # Create security monitoring script
    local monitor_script="/usr/local/bin/wordpress-security-monitor"
    sudo tee "$monitor_script" >/dev/null <<'EOF'
#!/bin/bash
# WordPress Security Monitor

LOG_FILE="/var/log/wordpress-security.log"
WP_ROOT="'$(load_state "WP_ROOT")'"

# Check for suspicious files
echo "[$(date)] Security check started" >> "$LOG_FILE"

# Check for PHP files in uploads
suspicious_files=$(find "$WP_ROOT/wp-content/uploads" -name "*.php" -type f 2>/dev/null)
if [ -n "$suspicious_files" ]; then
    echo "[WARNING] PHP files found in uploads:" >> "$LOG_FILE"
    echo "$suspicious_files" >> "$LOG_FILE"
fi

# Check for recently modified core files
find "$WP_ROOT/wp-admin" "$WP_ROOT/wp-includes" -name "*.php" -mtime -1 >> "$LOG_FILE"

# Check failed login attempts
grep "POST /wp-login.php" /var/log/nginx/*access.log | tail -20 >> "$LOG_FILE"

echo "[$(date)] Security check completed" >> "$LOG_FILE"
EOF
    
    sudo chmod +x "$monitor_script"
    
    # Add to cron
    (sudo crontab -l 2>/dev/null; echo "0 */6 * * * $monitor_script") | sudo crontab -
}

generate_security_report() {
    info "Generating security report..."
    
    local report_file="$HOME/wordpress-security-report.txt"
    local wp_root=$(load_state "WP_ROOT")
    
    {
        echo "=== WordPress Security Report ==="
        echo "Generated: $(date)"
        echo "Domain: $(load_state "DOMAIN")"
        echo
        
        echo "== User Configuration =="
        echo "WordPress User: $(load_state "WP_USER")"
        echo "PHP-FPM User: $(load_state "PHP_USER")"
        echo "Backup User: $(load_state "BACKUP_USER")"
        echo
        
        echo "== Security Features =="
        echo "WAF Type: $(load_state "WAF_TYPE")"
        echo "SSL Type: $(load_state "SSL_TYPE")"
        echo "Redis Cache: $(load_state "ENABLE_REDIS")"
        echo
        
        echo "== Firewall Status =="
        sudo ufw status numbered
        echo
        
        echo "== Fail2ban Status =="
        sudo fail2ban-client status
        echo
        
        echo "== File Permissions =="
        ls -la "$wp_root/wp-config.php" 2>/dev/null || echo "wp-config.php not found"
        echo
        
        echo "== Active Services =="
        systemctl is-active nginx php*-fpm mariadb fail2ban
        echo
        
        echo "== Recent Security Events =="
        sudo journalctl -u fail2ban -n 10 --no-pager
        
    } > "$report_file"
    
    info "Security report saved to: $report_file"
}

# Additional security functions
check_security_status() {
    info "=== Security Status Check ==="
    
    # Check fail2ban
    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban is active"
        sudo fail2ban-client status wordpress-auth 2>/dev/null || true
    else
        error "Fail2ban is not running"
    fi
    
    # Check firewall
    if sudo ufw status | grep -q "Status: active"; then
        success "Firewall is active"
    else
        error "Firewall is not active"
    fi
    
    # Check file integrity
    local wp_root=$(load_state "WP_ROOT")
    if [ -f "$wp_root/wp-config.php" ]; then
        if lsattr "$wp_root/wp-config.php" 2>/dev/null | grep -q "i"; then
            info "wp-config.php is immutable"
        fi
    fi
}

debug "Security module loaded successfully"