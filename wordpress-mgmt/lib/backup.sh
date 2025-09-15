#!/bin/bash
# wordpress-mgmt/lib/backup.sh - Backup system configuration
# Version: 3.0.5

setup_backup_system() {
    info "Setting up backup system..."
    
    if state_exists "BACKUP_CONFIGURED"; then
        info "✓ Backup system already configured"
        return 0
    fi
    
    # Setup steps
    show_progress 1 5 "Creating backup structure"
    create_backup_structure
    
    show_progress 2 5 "Installing backup scripts"
    install_backup_scripts
    
    show_progress 3 5 "Configuring backup credentials"
    setup_backup_credentials
    
    show_progress 4 5 "Setting up backup schedule"
    configure_backup_schedule
    
    show_progress 5 5 "Testing backup system"
    test_backup_system
    
    save_state "BACKUP_CONFIGURED" "true"
    success "✓ Backup system configured"
}

create_backup_structure() {
    local backup_user=$(load_state "BACKUP_USER")
    local wp_root=$(load_state "WP_ROOT")
    
    info "Creating backup directories..."
    
    # Backup directories
    local backup_dirs=(
        "/home/$backup_user/backups"
        "/home/$backup_user/backups/daily"
        "/home/$backup_user/backups/weekly"
        "/home/$backup_user/backups/monthly"
        "/home/$backup_user/logs"
        "$wp_root/backups"
    )
    
    for dir in "${backup_dirs[@]}"; do
        sudo mkdir -p "$dir"
    done
    
    # Set ownership
    sudo chown -R "$backup_user:$backup_user" "/home/$backup_user/backups"
    sudo chown -R "$backup_user:$backup_user" "/home/$backup_user/logs"
    sudo chown "$backup_user:wordpress" "$wp_root/backups"
    sudo chmod 750 "$wp_root/backups"
}

install_backup_scripts() {
    local backup_user=$(load_state "BACKUP_USER")
    local wp_root=$(load_state "WP_ROOT")
    local domain=$(load_state "DOMAIN")
    local db_name=$(load_state "DB_NAME")
    
    info "Installing backup scripts..."
    
    # Database backup script with proper variable handling
    sudo tee "/home/$backup_user/backup-database.sh" >/dev/null <<'EOF'
#!/bin/bash
# Database backup script - variables loaded from environment

# Load configuration from state file
if [ -f "/home/wp-backup/.backup_config" ]; then
    source "/home/wp-backup/.backup_config"
else
    echo "Configuration file not found" >&2
    exit 1
fi

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/db_${DB_NAME}_${DATE}.sql.gz"

# Create backup with explicit database specification
mysqldump --defaults-file="$HOME/.my.cnf" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --databases "$DB_NAME" | gzip > "$BACKUP_FILE"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "db_${DB_NAME}_*.sql.gz" -mtime +7 -delete

# Output backup file path for remote backup system
echo "$BACKUP_FILE"
EOF

    # Create configuration file for backup scripts
    sudo tee "/home/$backup_user/.backup_config" >/dev/null <<EOF
# Backup configuration - sourced by backup scripts
DOMAIN="$domain"
WP_ROOT="$wp_root"
DB_NAME="$db_name"
BACKUP_USER="$backup_user"
BACKUP_DIR="/home/$backup_user/db-backups"
EOF

    # Main backup script with wrapper script usage
    sudo tee "/home/$backup_user/backup-wordpress.sh" >/dev/null <<'EOF'
#!/bin/bash
# WordPress Backup Script
set -euo pipefail

# Load configuration
if [ -f "$HOME/.backup_config" ]; then
    source "$HOME/.backup_config"
else
    echo "Configuration file not found" >&2
    exit 1
fi

# Set working directory to user home to avoid getcwd errors
cd "$HOME"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE="$HOME/backups"
LOG_FILE="$HOME/logs/backup_${DATE}.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Start backup
log "Starting WordPress backup for $DOMAIN"

# Determine backup type (daily/weekly/monthly)
DAY_OF_WEEK=$(date +%u)
DAY_OF_MONTH=$(date +%d)

if [ "$DAY_OF_MONTH" -eq 1 ]; then
    BACKUP_TYPE="monthly"
    RETENTION_DAYS=180
elif [ "$DAY_OF_WEEK" -eq 7 ]; then
    BACKUP_TYPE="weekly"
    RETENTION_DAYS=30
else
    BACKUP_TYPE="daily"
    RETENTION_DAYS=7
fi

BACKUP_DIR="$BACKUP_BASE/$BACKUP_TYPE"
BACKUP_NAME="${DOMAIN}_backup_${DATE}"
TEMP_DIR="/tmp/$BACKUP_NAME"

# Create temporary directory
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Backup database
log "Backing up database..."
if "$HOME/backup-database.sh" > "$TEMP_DIR/db.sql"; then
    gzip "$TEMP_DIR/db.sql"
    log "Database backup completed"
else
    log "Database backup failed"
    exit 1
fi

# Copy configuration (using wrapper)
log "Copying configuration..."
if sudo /usr/local/bin/backup-wp-files copy-config "" "$TEMP_DIR"; then
    log "Configuration copied"
else
    log "Failed to copy wp-config.php"
    exit 1
fi

# Backup wp-content (using wrapper)  
log "Backing up wp-content..."
if sudo /usr/local/bin/backup-wp-files copy-content "" "$TEMP_DIR"; then
    log "wp-content backup completed"
else
    log "wp-content backup failed"
    exit 1
fi

# Create archive
log "Creating archive..."
cd /tmp
tar -czf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

# Generate checksum
cd "$BACKUP_DIR"
sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"

# Clean up old backups
log "Cleaning old backups..."
find "$BACKUP_DIR" -name "${DOMAIN}_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "${DOMAIN}_backup_*.tar.gz.sha256" -mtime +$RETENTION_DAYS -delete

# Report
BACKUP_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)
log "Backup completed: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)"

# Create latest symlink for remote backup
ln -sf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" "$BACKUP_BASE/latest-${BACKUP_TYPE}.tar.gz"

# Output for remote backup system
echo "BACKUP_FILE=$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "BACKUP_SIZE=$BACKUP_SIZE"
echo "BACKUP_TYPE=$BACKUP_TYPE"

exit 0
EOF

    # Set permissions for all scripts and config
    sudo chown "$backup_user:$backup_user" "/home/$backup_user"/.backup_config
    sudo chmod 600 "/home/$backup_user"/.backup_config
    sudo chown "$backup_user:$backup_user" /home/$backup_user/*.sh
    sudo chmod 750 /home/$backup_user/*.sh
}

setup_backup_credentials() {
    local backup_user=$(load_state "BACKUP_USER")
    local admin_email=$(load_state "ADMIN_EMAIL")
    
    info "Setting up backup credentials..."
    
    # SMTP credentials for notifications (optional)
    if confirm "Configure email notifications for backup status?" N; then
        echo
        get_input "SMTP server" "smtp.gmail.com"
        local smtp_server="$INPUT_RESULT"
        
        get_input "SMTP port" "587"
        local smtp_port="$INPUT_RESULT"
        
        get_input "SMTP username" "$admin_email"
        local smtp_user="$INPUT_RESULT"
        
        get_input "SMTP password" "" true
        local smtp_pass="$INPUT_RESULT"
        
        # Save credentials securely
        sudo tee "/home/$backup_user/.smtp_credentials" >/dev/null <<EOF
export SMTP_SERVER="$smtp_server"
export SMTP_PORT="$smtp_port"
export SMTP_USER="$smtp_user"
export SMTP_PASS="$smtp_pass"
export NOTIFY_EMAIL="$admin_email"
EOF
        
        sudo chown "$backup_user:$backup_user" "/home/$backup_user/.smtp_credentials"
        sudo chmod 600 "/home/$backup_user/.smtp_credentials"
        
        # Install msmtp for email sending
        sudo apt-get install -y msmtp msmtp-mta
        
        # Configure msmtp
        sudo -u "$backup_user" tee "/home/$backup_user/.msmtprc" >/dev/null <<EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        default
host           $smtp_server
port           $smtp_port
from           $smtp_user
user           $smtp_user
password       $smtp_pass
EOF
        
        sudo chmod 600 "/home/$backup_user/.msmtprc"
    fi
}

configure_backup_schedule() {
    local backup_user=$(load_state "BACKUP_USER")
    
    info "Configuring backup schedule..."
    
    # Create cron jobs
    local cron_content="# WordPress Backup Schedule
# Daily backups at 3 AM
0 3 * * * /home/$backup_user/backup-wordpress.sh >/dev/null 2>&1

# Quick database backup every 6 hours
0 */6 * * * /home/$backup_user/quick-backup.sh >/dev/null 2>&1

# Cleanup old quick backups daily
30 3 * * * find /home/$backup_user/backups -name 'quick_db_*.sql.gz' -mtime +2 -delete
"
    
    echo "$cron_content" | sudo crontab -u "$backup_user" -
    
    info "Backup schedule configured"
}

test_backup_system() {
    local backup_user=$(load_state "BACKUP_USER")
    
    info "Testing backup system..."
    
    # Run a test backup
    if sudo -u "$backup_user" /home/$backup_user/backup-wordpress.sh; then
        success "Backup test completed successfully"
        
        # Check if backup file was created
        local latest_backup=$(sudo -u "$backup_user" ls -t /home/$backup_user/backups/*/*.tar.gz 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            local backup_size=$(du -h "$latest_backup" | cut -f1)
            info "Test backup created: $(basename "$latest_backup") ($backup_size)"
        fi
    else
        error "Backup test failed"
        return 1
    fi
}

# Manual backup function
create_manual_backup() {
    local backup_user=$(load_state "BACKUP_USER")
    
    info "Creating manual backup..."
    
    if sudo -u "$backup_user" /home/$backup_user/backup-wordpress.sh; then
        success "Manual backup completed"
    else
        error "Manual backup failed"
        return 1
    fi
}

# Backup status function
check_backup_status() {
    local backup_user=$(load_state "BACKUP_USER")
    
    info "=== Backup Status ==="
    
    # List recent backups
    echo "Recent backups:"
    sudo -u "$backup_user" find /home/$backup_user/backups -name "*.tar.gz" -type f -mtime -7 -exec ls -lh {} \; | tail -10
    
    # Check cron jobs
    echo
    echo "Scheduled backups:"
    sudo crontab -u "$backup_user" -l
    
    # Check last backup log
    local last_log=$(sudo -u "$backup_user" ls -t /home/$backup_user/logs/backup_*.log 2>/dev/null | head -1)
    if [ -n "$last_log" ]; then
        echo
        echo "Last backup log:"
        sudo tail -20 "$last_log"
    fi
}

debug "Backup module loaded successfully"
