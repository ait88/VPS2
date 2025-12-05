#!/bin/bash
# wordpress-mgmt/lib/users.sh - User management with security isolation
# Version: 3.0.3 (SFTP Integration)

setup_users() {
    info "Setting up users with security isolation..."

    if state_exists "USERS_CONFIGURED"; then
        info "✓ Users already configured"
        return 0
    fi

    # Define users for service isolation
    local wp_user="${WP_USER:-wpuser}"
    local php_user="${PHP_USER:-php-fpm}"
    local redis_user="${REDIS_USER:-redis}"
    local backup_user="${BACKUP_USER:-wp-backup}"
    local sftp_user="wp-sftp" # New SFTP user

    # Save user configuration
    save_state "WP_USER" "$wp_user"
    save_state "PHP_USER" "$php_user"
    save_state "REDIS_USER" "$redis_user"
    save_state "BACKUP_USER" "$backup_user"
    save_state "SFTP_USER" "$sftp_user"

    # Create users
    show_progress 1 6 "Creating system users"
    create_system_users "$wp_user" "$php_user" "$redis_user" "$backup_user" "$sftp_user"

    # Setup security groups
    show_progress 2 6 "Configuring security groups"
    setup_security_groups "$wp_user" "$php_user" "$backup_user" "$sftp_user"

    # Configure backup access
    show_progress 3 6 "Setting up backup user access"
    setup_backup_user "$backup_user" "$wp_user"

    # Setup directory structure
    show_progress 4 6 "Creating directory structure"
    setup_directory_structure "$wp_user"

    # Configure sudo restrictions
    show_progress 5 6 "Applying sudo restrictions"
    configure_sudo_restrictions "$wp_user" "$php_user" "$redis_user" "$backup_user" "$sftp_user"

    # Verify setup
    show_progress 6 6 "Verifying user configuration"
    verify_user_setup "$wp_user" "$php_user" "$redis_user" "$backup_user" "$sftp_user"

    save_state "USERS_CONFIGURED" "true"
    success "✓ Users configured with security isolation"
}

create_system_users() {
    local wp_user=$1
    local php_user=$2
    local redis_user=$3
    local backup_user=$4
    local sftp_user=$5
    
    # WordPress user (owns WordPress files)
    if ! id "$wp_user" &>/dev/null; then
        info "Creating WordPress user: $wp_user"
        sudo useradd -r -s /bin/bash -d "/home/$wp_user" -m "$wp_user"
        # Lock password - no direct login
        sudo passwd -l "$wp_user"
    fi
    
    # PHP-FPM user (runs PHP processes)
    if ! id "$php_user" &>/dev/null; then
        info "Creating PHP-FPM user: $php_user"
        sudo useradd -r -s /usr/sbin/nologin -d /nonexistent -M "$php_user"
        sudo passwd -l "$php_user"
    fi
    
    # Redis user (if not exists from package)
    if ! id "$redis_user" &>/dev/null; then
        info "Creating Redis user: $redis_user"
        sudo useradd -r -s /usr/sbin/nologin -d /var/lib/redis -M "$redis_user"
        sudo passwd -l "$redis_user"
    fi
    
    # Backup user (read-only access)
    if ! id "$backup_user" &>/dev/null; then
        info "Creating backup user: $backup_user"
        sudo useradd -r -s /bin/bash -d "/home/$backup_user" -m "$backup_user"
        sudo passwd -l "$backup_user"
    fi
    
    # Fix backup user home directory ownership (security fix)
    if [ -d "/home/$backup_user" ]; then
        sudo chown -R "$backup_user:$backup_user" "/home/$backup_user"
        sudo chmod 750 "/home/$backup_user"
        debug "Fixed backup user home directory ownership"
    fi

    # SFTP user (for file uploads, chrooted)
    if [ "$(load_state "ENABLE_SFTP")" = "true" ]; then
        if ! id "$sftp_user" &>/dev/null; then
            info "Creating SFTP user: $sftp_user"
            sudo useradd -s /sbin/nologin -d "/var/sftp/$sftp_user" -M "$sftp_user"
            # Set a password for the SFTP user
            local sftp_pass=$(load_state "SFTP_PASS")
            echo "$sftp_user:$sftp_pass" | sudo chpasswd
            info "SFTP user password set"
        fi
    fi
}

setup_security_groups() {
    local wp_user=$1
    local php_user=$2
    local backup_user=$3
    local sftp_user=$4
    
    # Create WordPress group for shared access
    if ! getent group wordpress &>/dev/null; then
        sudo groupadd wordpress
    fi
    
    # Create web group for nginx/php coordination
    if ! getent group web &>/dev/null; then
        sudo groupadd web
    fi

    # Create sftp-users group for SSH chroot matching
    if ! getent group sftp-users &>/dev/null; then
        sudo groupadd sftp-users
    fi
    
    # Add users to appropriate groups
    sudo usermod -a -G wordpress "$wp_user"
    sudo usermod -a -G wordpress "$php_user"
    sudo usermod -a -G wordpress "$backup_user"
    if [ "$(load_state "ENABLE_SFTP")" = "true" ]; then
        sudo usermod -a -G wordpress "$sftp_user"
        sudo usermod -a -G sftp-users "$sftp_user"
    fi
    
    # Add PHP user to web group (for nginx coordination)
    sudo usermod -a -G web "$php_user"
    sudo usermod -a -G web www-data  # nginx user
    
    debug "Security groups configured"
}

setup_backup_user() {
    local backup_user=$1
    local wp_user=$2
    
    # Setup SSH directory
    local ssh_dir="/home/$backup_user/.ssh"
    sudo mkdir -p "$ssh_dir"
    
    # Add default backup key
    local backup_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKk1nsYyDbYzYL5UXEc8X9IDBIJECt9mQzy307M6h7p5"
    echo "$backup_key" | sudo tee "$ssh_dir/authorized_keys" >/dev/null
    
    # Prompt for additional keys
    echo
    while confirm "Add additional backup worker SSH key?" N; do
        echo
        read -p "Paste SSH public key: " extra_key
        if [[ "$extra_key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
            echo "$extra_key" | sudo tee -a "$ssh_dir/authorized_keys" >/dev/null
            success "Key added"
        else
            warning "Invalid SSH key format"
        fi
    done
    
    # Secure SSH directory
    sudo chmod 700 "$ssh_dir"
    sudo chmod 600 "$ssh_dir/authorized_keys"
    sudo chown -R "$backup_user:$backup_user" "$ssh_dir"
    
    # Add backup user to wordpress group for read access
    sudo usermod -a -G wordpress "$backup_user"
    
    # Create a backup wrapper script for secure operations
    sudo tee "/usr/local/bin/backup-wp-files" >/dev/null <<'EOF'
#!/bin/bash
# WordPress backup file operations wrapper
# Usage: backup-wp-files <operation> <source> <dest>

set -euo pipefail

OPERATION="$1"
WP_ROOT="/var/www/wordpress"
BACKUP_USER="wp-backup"

# Validate caller is backup user
if [ "$(whoami)" != "root" ] || [ "${SUDO_USER:-}" != "$BACKUP_USER" ]; then
    echo "Error: This script must be called via sudo by backup user only" >&2
    exit 1
fi

# Validate destination is in /tmp
case "$3" in
    /tmp/*)
        ;;
    *)
        echo "Error: Destination must be in /tmp" >&2
        exit 1
        ;;
esac

case "$OPERATION" in
    "copy-config")
        cp "$WP_ROOT/wp-config.php" "$3/"
        ;;
    "copy-content")
        rsync -a \
            --exclude='cache/' \
            --exclude='*.log' \
            --exclude='backup-*' \
            --exclude='upgrade/' \
            --exclude='uploads/backup-*' \
            "$WP_ROOT/wp-content/" "$3/wp-content/"
        chown -R "$BACKUP_USER:$BACKUP_USER" "$3/wp-content/"
        ;;
    *)
        echo "Error: Invalid operation: $OPERATION" >&2
        exit 1
        ;;
esac
EOF

    sudo chmod 755 "/usr/local/bin/backup-wp-files"
    
    # Simple sudoers rule for the wrapper script
    sudo tee "/etc/sudoers.d/backup-wordpress" >/dev/null <<EOF
# WordPress Backup User - Secure backup operations via wrapper
$backup_user ALL=(root) NOPASSWD: /usr/local/bin/backup-wp-files *
EOF
    
    # Configure restricted shell for backup user
    setup_backup_restrictions "$backup_user"
}

setup_backup_restrictions() {
    local backup_user=$1
    
    # Create restricted commands directory
    local restricted_dir="/home/$backup_user/bin"
    sudo mkdir -p "$restricted_dir"
    
    # Create wrapper scripts for allowed commands
    cat <<'EOF' | sudo tee "$restricted_dir/rsync-backup" >/dev/null
#!/bin/bash
# Restricted rsync for backups only
exec /usr/bin/rsync --server --sender -vlogDtprze.iLsfxC . "$@"
EOF
    
    sudo chmod 755 "$restricted_dir/rsync-backup"
    
    # Update SSH configuration for command restriction
    local sshd_config="/etc/ssh/sshd_config.d/50-backup-user.conf"
    cat <<EOF | sudo tee "$sshd_config" >/dev/null
# Backup user restrictions
Match User $backup_user
    ForceCommand /home/$backup_user/bin/rsync-backup
    PasswordAuthentication no
    X11Forwarding no
    AllowTcpForwarding no
    PermitTunnel no
EOF
    
    debug "Backup user restrictions configured"
}

setup_directory_structure() {
    local wp_user=$1
    local wp_root=$(load_state "WP_ROOT" "/var/www/wordpress")
    
    # Create directory structure
    local directories=(
        "$wp_root"
        "$wp_root/logs"
        "$wp_root/tmp"
        "$wp_root/cache"
        "$wp_root/backups"
        "/var/log/wordpress"
    )
    
    for dir in "${directories[@]}"; do
        sudo mkdir -p "$dir"
    done
    
    # Set ownership and permissions
    sudo chown -R "$wp_user:wordpress" "$wp_root"
    sudo chmod 2750 "$wp_root"  # setgid for group inheritance
    
    # Special permissions for specific directories
    sudo chmod 2770 "$wp_root/logs"
    sudo chmod 2770 "$wp_root/tmp"
    sudo chmod 2770 "$wp_root/cache"
    sudo chmod 2750 "$wp_root/backups"  # Read-only for backup user
    
    # WordPress logs accessible to sysadmin
    sudo chown "$wp_user:wordpress" "/var/log/wordpress"
    sudo chmod 2770 "/var/log/wordpress"
    
    # Add sysadmin to wordpress group for management
    local admin_user=$(whoami)
    sudo usermod -a -G wordpress "$admin_user"
    
    debug "Directory structure created with secure permissions"
}

configure_sudo_restrictions() {
    local wp_user=$1
    local php_user=$2
    local redis_user=$3
    local backup_user=$4
    
    # Create sudoers.d file for WordPress management
    local sudoers_file="/etc/sudoers.d/wordpress-security"
    
    cat <<EOF | sudo tee "$sudoers_file" >/dev/null
# WordPress Security - User Restrictions
# Generated by setup-wordpress.sh

# Deny sudo access to service users
$wp_user ALL=(ALL) !ALL
$php_user ALL=(ALL) !ALL
$redis_user ALL=(ALL) !ALL
$backup_user ALL=(ALL) !ALL

# Allow sysadmin to switch to service users without password
%sudo ALL=(ALL) NOPASSWD: /bin/su - $wp_user
%sudo ALL=(ALL) NOPASSWD: /bin/su - $backup_user

# Allow wp-cli operations as WordPress user
%sudo ALL=($wp_user) NOPASSWD: /usr/local/bin/wp
EOF
    
    # Validate sudoers file
    if sudo visudo -c -f "$sudoers_file"; then
        debug "Sudo restrictions applied"
    else
        error "Sudoers file validation failed"
        sudo rm -f "$sudoers_file"
        return 1
    fi
}

verify_user_setup() {
    local wp_user=$1
    local php_user=$2
    local redis_user=$3
    local backup_user=$4
    
    local all_good=true
    
    # Verify users exist
    for user in "$wp_user" "$php_user" "$redis_user" "$backup_user"; do
        if ! id "$user" &>/dev/null; then
            error "User not created: $user"
            all_good=false
        fi
    done
    
    # Verify groups
    for group in wordpress web; do
        if ! getent group "$group" &>/dev/null; then
            error "Group not created: $group"
            all_good=false
        fi
    done
    
    # Verify backup SSH setup
    if [ ! -f "/home/$backup_user/.ssh/authorized_keys" ]; then
        error "Backup SSH keys not configured"
        all_good=false
    fi
    
    # Verify directory permissions
    local wp_root=$(load_state "WP_ROOT" "/var/www/wordpress")
    if [ -d "$wp_root" ]; then
        local perms=$(stat -c %a "$wp_root")
        if [ "$perms" != "2750" ]; then
            warning "WordPress root permissions incorrect: $perms (expected 2750)"
        fi
    fi
    
    if ! $all_good; then
        error "User setup verification failed"
        return 1
    fi
    
    debug "All users verified successfully"
}

# Helper function to display user summary
show_user_summary() {
    info "=== User Configuration Summary ==="
    
    local wp_user=$(load_state "WP_USER")
    local php_user=$(load_state "PHP_USER")
    local redis_user=$(load_state "REDIS_USER")
    local backup_user=$(load_state "BACKUP_USER")
    
    cat <<EOF

WordPress User: $wp_user
  - Owns WordPress files
  - No direct login
  - Member of: wordpress group

PHP-FPM User: $php_user
  - Runs PHP processes
  - No shell access
  - Member of: wordpress, web groups

Redis User: $redis_user
  - Runs Redis cache
  - No shell access
  - Isolated from WordPress

Backup User: $backup_user
  - SSH access for backups only
  - Read-only WordPress access
  - Restricted rsync commands

Sysadmin ($(whoami)):
  - Full sudo access
  - Member of wordpress group
  - Can switch to any service user

EOF
}

# Cleanup function for reset
cleanup_users() {
    if ! confirm "Remove all WordPress-related users? This cannot be undone!" N; then
        return 1
    fi
    
    info "Removing users..."
    
    local users=(
        "$(load_state "WP_USER")"
        "$(load_state "PHP_USER")"
        "$(load_state "BACKUP_USER")"
    )
    
    for user in "${users[@]}"; do
        if [ -n "$user" ] && id "$user" &>/dev/null; then
            sudo userdel -r "$user" 2>/dev/null || true
        fi
    done
    
    # Remove groups
    for group in wordpress web; do
        sudo groupdel "$group" 2>/dev/null || true
    done
    
    # Remove sudo restrictions
    sudo rm -f /etc/sudoers.d/wordpress-security
    
    warning "Users removed"
}

debug "Users module loaded successfully"
