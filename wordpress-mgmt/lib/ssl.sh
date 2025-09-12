#!/bin/bash
# wordpress-mgmt/lib/ssl.sh - SSL/TLS configuration
# Version: 3.0.0

setup_ssl() {
    info "Setting up SSL/TLS..."
    
    if state_exists "SSL_CONFIGURED"; then
        info "✓ SSL already configured"
        return 0
    fi
    
    # Ensure firewall allows HTTP/HTTPS for SSL challenges
    ensure_ssl_firewall_rules
    
    local ssl_type=$(load_state "SSL_TYPE" "letsencrypt")
    local domain=$(load_state "DOMAIN")
    
    case "$ssl_type" in
        "letsencrypt")
            setup_letsencrypt "$domain"
            ;;
        "selfsigned")
            setup_selfsigned "$domain"
            ;;
        "manual")
            info "Manual SSL configuration selected - skipping"
            ;;
        "none")
            warning "No SSL configured - site will be HTTP only"
            update_nginx_http_only "$domain"
            ;;
    esac
    
    save_state "SSL_CONFIGURED" "true"
}

ensure_ssl_firewall_rules() {
    info "Ensuring firewall allows HTTP/HTTPS for SSL challenges..."
    
    # Check if UFW is active
    if ! sudo ufw status | grep -q "Status: active"; then
        debug "UFW is not active - enabling with basic rules"
        sudo ufw --force enable
    fi
    
    # Check if HTTP/HTTPS rules already exist
    local http_exists=$(sudo ufw status | grep -E "80/tcp|80 " | wc -l)
    local https_exists=$(sudo ufw status | grep -E "443/tcp|443 " | wc -l)
    
    local waf_type=$(load_state "WAF_TYPE" "none")
    
    if [ "$waf_type" = "none" ]; then
        # Direct access - allow from anywhere
        if [ "$http_exists" -eq 0 ]; then
            info "Adding HTTP (80) firewall rule..."
            sudo ufw allow 80/tcp comment "HTTP"
        fi
        
        if [ "$https_exists" -eq 0 ]; then
            info "Adding HTTPS (443) firewall rule..."
            sudo ufw allow 443/tcp comment "HTTPS"
        fi
    else
        # WAF setup - ensure basic rules exist for SSL challenges
        if [ "$http_exists" -eq 0 ] && [ "$https_exists" -eq 0 ]; then
            warning "WAF configured but no HTTP/HTTPS rules found"
            info "Adding temporary HTTP/HTTPS rules for SSL challenges..."
            sudo ufw allow 80/tcp comment "HTTP (SSL challenges)"
            sudo ufw allow 443/tcp comment "HTTPS (SSL challenges)"
            
            # Note: These will be refined by the security module later
        fi
    fi
    
    debug "Firewall rules verified for SSL setup"
}

setup_letsencrypt() {
    local domain=$1
    local include_www=$(load_state "INCLUDE_WWW" "true")
    local admin_email=$(load_state "ADMIN_EMAIL")
    local waf_type=$(load_state "WAF_TYPE" "none")
    
    info "Setting up Let's Encrypt SSL certificate..."
    
    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        info "Certificate already exists for $domain"
        if confirm "Renew existing certificate?" N; then
            sudo certbot renew --cert-name "$domain"
        fi
        update_nginx_ssl "$domain" "letsencrypt"
        return 0
    fi
    
    # Prepare domain list - conditionally include www
    local domains="-d $domain"
    if [ "$include_www" = "true" ]; then
        # Check if www subdomain resolves before including it
        if dig +short "www.$domain" | grep -q "$(dig +short "$domain")"; then
            domains="$domains -d www.$domain"
            info "Including www.$domain in certificate (DNS resolves correctly)"
        else
            warning "Skipping www.$domain - DNS does not resolve to same IP as $domain"
            # Update state to reflect reality
            save_state "INCLUDE_WWW" "false"
        fi
    fi
    
    # WAF considerations
    if [ "$waf_type" != "none" ]; then
        warning "WAF detected - ensure DNS is pointing through WAF before proceeding"
        if ! confirm "Is DNS properly configured through your WAF?" Y; then
            error "Please configure DNS before setting up SSL"
            return 1
        fi
    fi
    
    # Ensure ACME challenge directory exists (defensive programming)
    local wp_root=$(load_state "WP_ROOT")
    local wp_user=$(load_state "WP_USER")

    if [ ! -d "$wp_root/.well-known/acme-challenge" ]; then
        info "Creating ACME challenge directory..."
        sudo mkdir -p "$wp_root/.well-known/acme-challenge/"
        sudo chown -R "$wp_user:wordpress" "$wp_root/.well-known/"
        sudo chmod -R 755 "$wp_root/.well-known/"
    fi

    # Obtain certificate - nginx config should already be correct for ACME
    info "Obtaining Let's Encrypt certificate..."
    
    # Use webroot method - ACME challenge location is already configured correctly
    sudo certbot certonly \
        --webroot \
        --webroot-path "$(load_state "WP_ROOT")" \
        --email "$admin_email" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        $domains
    
    if [ $? -eq 0 ]; then
        success "SSL certificate obtained successfully"
        update_nginx_ssl "$domain" "letsencrypt"
        setup_auto_renewal
    else
        error "Failed to obtain SSL certificate"
        
        # Fallback options
        if confirm "Use self-signed certificate as fallback?" Y; then
            setup_selfsigned "$domain"
        fi
        return 1
    fi
}

setup_cloudflare_origin_ssl() {
    local domain=$1
    local include_www=$(load_state "INCLUDE_WWW" "true")
    
    info "Setting up Cloudflare Origin Certificate..."
    
    # Check if already exists
    if [ -f "/etc/ssl/certs/${domain}-origin.crt" ]; then
        info "Origin certificate already exists"
        update_nginx_ssl "$domain" "cloudflare_origin"
        return 0
    fi
    
    echo
    echo "To use Cloudflare Origin Certificates:"
    echo "1. Go to Cloudflare Dashboard → SSL/TLS → Origin Server"
    echo "2. Click 'Create Certificate'"
    echo "3. Select 'Let Cloudflare generate a private key and a CSR'"
    echo "4. Add hostnames: $domain$([ "$include_www" = "true" ] && echo ", www.$domain")"
    echo "5. Choose 'RSA (2048)' key type"
    echo "6. Set validity to 15 years"
    echo "7. Copy the certificate and private key"
    echo
    
    # Get certificate from user
    echo "Paste the Origin Certificate (including -----BEGIN/END lines):"
    echo "Press Ctrl+D when finished:"
    local cert_content
    cert_content=$(cat)
    
    echo
    echo "Paste the Private Key (including -----BEGIN/END lines):"
    echo "Press Ctrl+D when finished:"
    local key_content
    key_content=$(cat)
    
    # Validate content
    if [[ ! "$cert_content" =~ "-----BEGIN CERTIFICATE-----" ]] || [[ ! "$key_content" =~ "-----BEGIN PRIVATE KEY-----" ]]; then
        error "Invalid certificate or key format"
        return 1
    fi
    
    # Save certificate and key
    echo "$cert_content" | sudo tee "/etc/ssl/certs/${domain}-origin.crt" >/dev/null
    echo "$key_content" | sudo tee "/etc/ssl/private/${domain}-origin.key" >/dev/null
    
    # Set permissions
    sudo chmod 644 "/etc/ssl/certs/${domain}-origin.crt"
    sudo chmod 600 "/etc/ssl/private/${domain}-origin.key"
    
    # Download Cloudflare Origin CA root (for authenticated origin pulls)
    if [ "$(load_state "CF_AUTH_ORIGIN_PULLS")" = "true" ]; then
        sudo curl -fsSL -o /etc/nginx/cloudflare-origin-pull-ca.pem \
            https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
        sudo chmod 644 /etc/nginx/cloudflare-origin-pull-ca.pem
    fi
    
    update_nginx_ssl "$domain" "cloudflare_origin"
    success "Cloudflare Origin Certificate installed"
}

setup_selfsigned() {
    local domain=$1
    
    info "Creating self-signed SSL certificate..."
    
    # Create private key
    sudo openssl genrsa -out "/etc/ssl/private/${domain}.key" 2048
    
    # Create certificate
    sudo openssl req -new -x509 -days 365 \
        -key "/etc/ssl/private/${domain}.key" \
        -out "/etc/ssl/certs/${domain}.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain"
    
    # Set permissions
    sudo chmod 600 "/etc/ssl/private/${domain}.key"
    sudo chmod 644 "/etc/ssl/certs/${domain}.crt"
    
    update_nginx_ssl "$domain" "selfsigned"
    
    warning "Self-signed certificate created - browsers will show security warning"
}

cleanup_temporary_certificates() {
    local temp_cert="/etc/ssl/certs/nginx-selfsigned.crt"
    local temp_key="/etc/ssl/private/nginx-selfsigned.key"
    
    if [ -f "$temp_cert" ] && [ -f "$temp_key" ]; then
        debug "Cleaning up temporary SSL certificates..."
        sudo rm -f "$temp_cert" "$temp_key"
    fi
}

update_nginx_ssl() {
    local domain=$1
    local ssl_type=$2
    local nginx_conf="/etc/nginx/sites-available/$domain"
    
    info "Updating Nginx SSL configuration..."
    
    # Backup existing config
    backup_file "$nginx_conf"
    
    # Determine certificate paths
    local cert_path
    local key_path
    
    case "$ssl_type" in
        "letsencrypt")
            cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
            key_path="/etc/letsencrypt/live/$domain/privkey.pem"
            ;;
        "selfsigned")
            cert_path="/etc/ssl/certs/${domain}.crt"
            key_path="/etc/ssl/private/${domain}.key"
            ;;
    esac
    
    # Update SSL certificate paths
    sudo sed -i "s|ssl_certificate .*|ssl_certificate $cert_path;|" "$nginx_conf"
    sudo sed -i "s|ssl_certificate_key .*|ssl_certificate_key $key_path;|" "$nginx_conf"
    
    # Add SSL optimization
    if ! grep -q "ssl_protocols" "$nginx_conf"; then
        sudo sed -i "/ssl_certificate_key/a\\\n    # SSL Configuration\\n    ssl_protocols TLSv1.2 TLSv1.3;\\n    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';\\n    ssl_prefer_server_ciphers off;\\n    ssl_session_cache shared:SSL:10m;\\n    ssl_session_timeout 10m;\\n    ssl_stapling on;\\n    ssl_stapling_verify on;\\n    resolver 8.8.8.8 8.8.4.4 valid=300s;\\n    resolver_timeout 5s;" "$nginx_conf"
    fi
    
    # Add HSTS header (if not WAF)
    local waf_type=$(load_state "WAF_TYPE" "none")
    if [ "$waf_type" = "none" ]; then
        sudo sed -i 's|# add_header Strict-Transport-Security|add_header Strict-Transport-Security|' /etc/nginx/snippets/security-headers.conf
    fi
    
    # Clean up temporary certificates if they exist
    cleanup_temporary_certificates
    
    # Test and reload
    if sudo nginx -t; then
        restart_service "nginx"
        success "SSL configuration updated"
    else
        error "Nginx configuration error"
        sudo mv "${nginx_conf}.backup"* "$nginx_conf"
        return 1
    fi
}

update_nginx_http_only() {
    local domain=$1
    local nginx_conf="/etc/nginx/sites-available/$domain"
    
    info "Configuring HTTP-only access..."
    
    # Remove HTTPS server block
    sudo sed -i '/^server {.*listen 443/,/^}/d' "$nginx_conf"
    
    # Update HTTP server block
    sudo sed -i '/return 301 https/d' "$nginx_conf"
    sudo sed -i '/server_name/a\    root '"$(load_state "WP_ROOT")"';' "$nginx_conf"
    
    restart_service "nginx"
}

setup_auto_renewal() {
    info "Setting up automatic certificate renewal..."
    
    # Create renewal hook script
    sudo tee /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh >/dev/null <<'EOF'
#!/bin/bash
systemctl reload nginx
EOF
    
    sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
    
    # Test renewal
    if sudo certbot renew --dry-run; then
        success "Automatic renewal configured"
    else
        warning "Automatic renewal test failed - check manually"
    fi
}

# Cloudflare Origin CA certificate support
setup_cloudflare_origin_cert() {
    local domain=$1
    
    info "Setting up Cloudflare Origin Certificate..."
    
    echo "Please generate an Origin Certificate in Cloudflare dashboard:"
    echo "1. Go to SSL/TLS > Origin Server"
    echo "2. Create Certificate"
    echo "3. Copy the certificate and private key"
    
    read -p "Paste the certificate (end with blank line): " -d '' cf_cert
    read -p "Paste the private key (end with blank line): " -d '' cf_key
    
    # Save certificate and key
    echo "$cf_cert" | sudo tee "/etc/ssl/certs/${domain}-cf.crt" >/dev/null
    echo "$cf_key" | sudo tee "/etc/ssl/private/${domain}-cf.key" >/dev/null
    
    # Set permissions
    sudo chmod 600 "/etc/ssl/private/${domain}-cf.key"
    sudo chmod 644 "/etc/ssl/certs/${domain}-cf.crt"
    
    # Download Cloudflare Origin CA root
    sudo curl -o /etc/nginx/cloudflare-origin-pull-ca.pem \
        https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem
    
    # Update Nginx to use Origin certificate
    update_nginx_ssl "$domain" "cloudflare"
}

# Check SSL certificate status
check_ssl_status() {
    local domain=$(load_state "DOMAIN")
    
    info "=== SSL Certificate Status ==="
    
    # Check Let's Encrypt
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo "Let's Encrypt certificate found:"
        sudo certbot certificates --cert-name "$domain"
    fi
    
    # Check self-signed
    if [ -f "/etc/ssl/certs/${domain}.crt" ]; then
        echo "Self-signed certificate found:"
        openssl x509 -in "/etc/ssl/certs/${domain}.crt" -noout -dates
    fi
    
    # Test HTTPS
    if curl -sSf "https://$domain" >/dev/null 2>&1; then
        success "HTTPS is working"
    else
        warning "HTTPS test failed"
    fi
}

debug "SSL module loaded successfully"
