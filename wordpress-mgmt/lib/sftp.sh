#!/bin/bash
# wordpress-mgmt/lib/sftp.sh - Dedicated SFTP user setup
# Version: 1.0.0

setup_sftp_user() {
    if [ "$(load_state "ENABLE_SFTP")" != "true" ]; then
        info "SFTP user setup is disabled in the configuration."
        return 0
    fi

    info "Setting up dedicated SFTP user..."

    if state_exists "SFTP_CONFIGURED"; then
        info "✓ SFTP user already configured"
        return 0
    fi

    show_progress 1 5 "Configuring SSH for SFTP chroot"
    configure_sftp_ssh_chroot

    show_progress 2 5 "Creating chroot directory and bind mount"
    create_sftp_chroot_structure

    show_progress 3 5 "Creating file watcher script"
    create_sftp_watcher_script

    show_progress 4 5 "Creating and enabling watcher service"
    create_sftp_watcher_service

    show_progress 5 5 "Verifying SFTP setup"
    verify_sftp_setup

    save_state "SFTP_CONFIGURED" "true"
    success "✓ Dedicated SFTP user configured successfully"
}

configure_sftp_ssh_chroot() {
    info "Configuring SSH daemon for SFTP chroot jail..."
    local sshd_config="/etc/ssh/sshd_config"

    # Backup sshd_config
    backup_file "$sshd_config"

    # Check if the configuration already exists
    if grep -q "Match Group sftp-users" "$sshd_config"; then
        info "SFTP chroot configuration already exists in sshd_config"
        return 0
    fi

    # Append SFTP chroot configuration
    sudo tee -a "$sshd_config" >/dev/null <<'EOF'

# SFTP Chroot Jail Configuration
Match Group sftp-users
    ChrootDirectory /var/sftp/%u
    ForceCommand internal-sftp
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
EOF

    # Restart SSH service to apply changes
    restart_service "ssh"
}

create_sftp_chroot_structure() {
    local wp_root=$(load_state "WP_ROOT")
    local sftp_user="wp-sftp"
    local jail_base="/var/sftp"
    local user_jail="$jail_base/$sftp_user"

    info "Creating SFTP chroot structure at $user_jail..."

    # Create base and user-specific jail directories
    sudo mkdir -p "$user_jail/html"

    # Set strict root ownership for chroot security
    sudo chown root:root "$jail_base"
    sudo chown root:root "$user_jail"
    sudo chmod 755 "$jail_base"
    sudo chmod 755 "$user_jail"

    # Bind mount the WordPress directory into the jail
    info "Bind mounting $wp_root to $user_jail/html..."
    sudo mount --bind "$wp_root" "$user_jail/html"

    # Make the bind mount permanent
    if ! grep -q "$user_jail/html" /etc/fstab; then
        echo "$wp_root $user_jail/html none bind 0 0" | sudo tee -a /etc/fstab >/dev/null
        success "Bind mount added to /etc/fstab"
    else
        info "Bind mount already present in /etc/fstab"
    fi
}

create_sftp_watcher_script() {
    local wp_root=$(load_state "WP_ROOT")
    local wp_user=$(load_state "WP_USER")
    local sftp_user="wp-sftp"
    local watcher_script="/usr/local/bin/sftp-chown-watcher.sh"

    info "Creating SFTP file ownership watcher script..."

    sudo tee "$watcher_script" >/dev/null <<EOF
#!/bin/bash
# Watches for files created by the sftp user and changes ownership.

WATCH_DIR="$wp_root"
SFTP_USER="$sftp_user"
TARGET_USER="$wp_user"
LOG_FILE="/var/log/sftp-watcher.log"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

log "Starting SFTP watcher for directory: \$WATCH_DIR"

inotifywait -m -r -e create -e moved_to --format '%w%f' "\$WATCH_DIR" | while read FILE; do
    if [ -e "\$FILE" ]; then
        FILE_OWNER=\$(stat -c '%U' "\$FILE")
        if [ "\$FILE_OWNER" = "\$SFTP_USER" ]; then
            log "Detected file upload: \$FILE"
            chown "\$TARGET_USER:wordpress" "\$FILE"
            log "Changed ownership of \$FILE to \$TARGET_USER:wordpress"
        fi
    fi
done
EOF

    sudo chmod +x "$watcher_script"
    success "Watcher script created at $watcher_script"
}

create_sftp_watcher_service() {
    local service_file="/etc/systemd/system/sftp-watcher.service"
    info "Creating systemd service for SFTP watcher..."

    sudo tee "$service_file" >/dev/null <<'EOF'
[Unit]
Description=SFTP File Ownership Watcher
After=network.target

[Service]
ExecStart=/usr/local/bin/sftp-chown-watcher.sh
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start the service
    sudo systemctl daemon-reload
    sudo systemctl enable sftp-watcher.service
    sudo systemctl start sftp-watcher.service

    success "sftp-watcher service created and started"
}

verify_sftp_setup() {
    local sftp_user="wp-sftp"
    local all_good=true

    # Verify user and group
    if ! id "$sftp_user" &>/dev/null; then
        error "SFTP user '$sftp_user' not found"
        all_good=false
    fi
    if ! getent group sftp-users &>/dev/null; then
        error "Group 'sftp-users' not found"
        all_good=false
    fi

    # Verify watcher service
    if ! sudo systemctl is-active --quiet sftp-watcher; then
        error "sftp-watcher service is not running"
        all_good=false
    fi

    if ! $all_good; then
        error "SFTP setup verification failed"
        return 1
    fi

    debug "SFTP setup verified successfully"
    return 0
}

debug "SFTP module loaded successfully"
