#!/bin/bash
# wordpress-mgmt/lib/database.sh - MariaDB setup and database management
# Version: 3.0.0

setup_database() {
    info "Setting up MariaDB database..."
    
    if state_exists "DATABASE_CONFIGURED"; then
        info "✓ Database already configured"
        return 0
    fi
    
    # Load configuration
    local db_name=$(load_state "DB_NAME")
    local db_user=$(load_state "DB_USER")
    local db_pass=$(load_state "DB_PASS")
    
    # Setup steps
    show_progress 1 5 "Securing MariaDB installation"
    secure_mariadb_installation
    
    show_progress 2 5 "Creating WordPress database"
    create_wordpress_database "$db_name" "$db_user" "$db_pass"
    
    show_progress 3 5 "Configuring MariaDB for WordPress"
    optimize_mariadb_config
    
    show_progress 4 5 "Setting up database backups"
    setup_database_backups "$db_name" "$db_user" "$db_pass"
    debug "Database backup setup completed"
    
    show_progress 5 5 "Verifying database setup"
    verify_database_setup "$db_name" "$db_user" "$db_pass"
    debug "Database verification completed"
    
    save_state "DATABASE_CONFIGURED" "true"
    success "✓ Database configured successfully"
}

handle_mariadb_auth_failure() {
    error "MariaDB authentication failed with both debian.cnf and socket authentication"
    echo
    warning "This usually means there's a conflicting MariaDB installation with different credentials."
    echo "The saved root password in setup_state doesn't match the current MariaDB root password."
    echo
    echo "Options to resolve this:"
    echo "1) Try to fix the authentication manually"
    echo "2) Reset MariaDB root password (requires manual intervention)"
    echo "3) NUKE IT! - Completely remove MariaDB and start fresh"
    echo
    echo -e "\033[1;31mWARNING: Option 3 will completely remove MariaDB and ALL existing databases!\033[0m"
    echo
    
    while true; do
        read -p "Enter your choice [1-3]: " auth_choice
        case $auth_choice in
            1)
                echo "Please fix MariaDB authentication manually and run the script again."
                echo "You can try: sudo mysql_secure_installation"
                return 1
                ;;
            2)
                echo "Please reset the MariaDB root password manually:"
                echo "1. sudo systemctl stop mariadb"
                echo "2. sudo mysqld_safe --skip-grant-tables &"
                echo "3. mysql -u root"
                echo "4. ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';"
                echo "5. FLUSH PRIVILEGES;"
                echo "6. exit"
                echo "7. sudo pkill mysqld"
                echo "8. sudo systemctl start mariadb"
                echo "Then update the DB_ROOT_PASS in wordpress-mgmt/setup_state"
                return 1
                ;;
            3)
                echo
                echo -e "\033[1;31m⚠️  DANGER ZONE ⚠️\033[0m"
                echo "This will completely remove MariaDB and ALL databases!"
                echo "Type 'I know what I'm doing, Nuke it!' to proceed:"
                read -p "> " nuke_confirm
                if [ "$nuke_confirm" = "I know what I'm doing, Nuke it!" ]; then
                    nuke_mariadb_installation
                    return $?
                else
                    echo "Confirmation failed. Aborting."
                    return 1
                fi
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

nuke_mariadb_installation() {
    info "🔥 NUKING MariaDB installation..."
    
    # Stop MariaDB service
    info "Stopping MariaDB service..."
    sudo systemctl stop mariadb || true
    sudo systemctl disable mariadb || true
    
    # Remove MariaDB packages
    info "Removing MariaDB packages..."
    sudo apt-get remove --purge -y mariadb-server mariadb-client mariadb-common mysql-common || true
    sudo apt-get autoremove -y || true
    
    # Remove MariaDB data directory
    info "Removing MariaDB data directory..."
    sudo rm -rf /var/lib/mysql
    
    # Remove configuration files
    info "Removing configuration files..."
    sudo rm -rf /etc/mysql
    sudo rm -f /etc/init.d/mysql
    sudo rm -f /etc/logrotate.d/mysql-server
    
    # Remove user credentials
    info "Removing user credentials..."
    rm -f "$HOME/.mysql_root"
    rm -f "$HOME/.my.cnf"
    
    # Clear database state
    info "Clearing database state..."
    remove_state "DATABASE_CONFIGURED"
    remove_state "DB_ROOT_PASS"
    
    # Optional: Remove WordPress files and users if they exist
    local wp_root=$(load_state "WP_ROOT")
    if [ -n "$wp_root" ] && [ -d "$wp_root" ]; then
        echo
        if confirm "Also remove WordPress files at $wp_root?" N; then
            info "Removing WordPress files..."
            sudo rm -rf "$wp_root"
            
            # Remove WordPress-related users
            local wp_user=$(load_state "WP_USER" "wp-user")
            local php_user=$(load_state "PHP_USER" "php-user")
            local backup_user=$(load_state "BACKUP_USER" "wp-backup")
            
            for user in "$wp_user" "$php_user" "$backup_user"; do
                if id "$user" &>/dev/null; then
                    info "Removing user: $user"
                    sudo userdel -r "$user" 2>/dev/null || true
                fi
            done
            
            # Clear WordPress-related state
            remove_state "USERS_CONFIGURED"
            remove_state "WORDPRESS_INSTALLED"
            remove_state "NGINX_CONFIGURED"
            remove_state "SSL_CONFIGURED"
            remove_state "SECURITY_CONFIGURED"
            remove_state "BACKUP_CONFIGURED"
        fi
    fi
    
    # Offer complete reset option
    echo
    if confirm "COMPLETE RESET: Clear ALL configuration and start completely fresh?" N; then
        info "🔥 COMPLETE RESET: Clearing all configuration..."
        
        # Backup current domain config in case user wants to reuse
        local domain=$(load_state "DOMAIN")
        local admin_email=$(load_state "ADMIN_EMAIL")
        
        # Remove the entire state file
        rm -f "$STATE_FILE"
        
        info "✓ All configuration cleared - script will start completely fresh"
        if [ -n "$domain" ]; then
            info "💡 TIP: Your previous domain was '$domain' and email was '$admin_email'"
            info "💡 You can reuse these when configuring fresh, or choose new ones"
        fi
        
        success "✓ Complete reset successful - restart the script to begin fresh setup"
        exit 0
    fi
    
    # Reinstall MariaDB
    info "Reinstalling MariaDB..."
    sudo apt-get update
    sudo apt-get install -y mariadb-server mariadb-client
    
    # Start MariaDB service
    info "Starting MariaDB service..."
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    
    # Wait for MariaDB to be ready
    info "Waiting for MariaDB to be ready..."
    local timeout=30
    local count=0
    while ! sudo mysqladmin ping --silent && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if [ $count -eq $timeout ]; then
        error "MariaDB failed to start after reinstallation"
        return 1
    fi
    
    success "✓ MariaDB has been nuked and reinstalled!"
    info "You can now continue with the installation process."
    
    # Generate new root password and secure the installation
    local root_pass=$(generate_password 32)
    save_state "DB_ROOT_PASS" "$root_pass"
    
    # Now secure the fresh installation
    secure_mariadb_installation
}

secure_mariadb_installation() {
    info "Securing MariaDB..."
    
    # Generate root password if not exists
    local root_pass=$(load_state "DB_ROOT_PASS")
    if [ -z "$root_pass" ]; then
        root_pass=$(generate_password 32)
        save_state "DB_ROOT_PASS" "$root_pass"
    fi
    
    # Check if MariaDB is already secured by testing root access
    if mysql -u root -p"$root_pass" -e "SELECT 1;" &>/dev/null; then
        info "MariaDB already secured with saved root password"
        # Update credentials file
        local creds_file="$HOME/.mysql_root"
        cat > "$creds_file" <<EOF
[client]
user=root
password=$root_pass
EOF
        chmod 600 "$creds_file"
        return 0
    fi
    
    # Try to secure MariaDB - first try with debian.cnf, then fallback to socket auth
    if ! sudo mysql --defaults-file=/etc/mysql/debian.cnf <<EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disable remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF
    then
        # Fallback: try connecting as root with socket authentication
        warning "Debian config failed, trying socket authentication..."
        if ! sudo mysql -u root <<EOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_pass';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disable remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Reload privilege tables
FLUSH PRIVILEGES;
EOF
        then
            # Both methods failed - handle gracefully
            handle_mariadb_auth_failure
            return $?
        fi
    fi
    
    # Save root credentials securely
    local creds_file="$HOME/.mysql_root"
    cat > "$creds_file" <<EOF
[client]
user=root
password=$root_pass
EOF
    chmod 600 "$creds_file"
    
    debug "MariaDB secured with root password"
}

create_wordpress_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    info "Creating database: $db_name"
    
    # Use appropriate credentials for database creation
    local root_pass=$(load_state "DB_ROOT_PASS")
    
    # Try root with saved password first, fallback to debian.cnf
    if ! mysql -u root -p"$root_pass" <<EOF
-- Create database with proper charset
CREATE DATABASE IF NOT EXISTS \`$db_name\`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_520_ci;

-- Create user (drop if exists for idempotency)
DROP USER IF EXISTS '$db_user'@'localhost';
CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';

-- Grant privileges
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';

-- Additional security - limit to localhost only
GRANT USAGE ON *.* TO '$db_user'@'localhost' REQUIRE NONE WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;

FLUSH PRIVILEGES;
EOF
    then
        # Fallback to debian.cnf
        sudo mysql --defaults-file=/etc/mysql/debian.cnf <<EOF
-- Create database with proper charset
CREATE DATABASE IF NOT EXISTS \`$db_name\`
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_520_ci;

-- Create user (drop if exists for idempotency)
DROP USER IF EXISTS '$db_user'@'localhost';
CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';

-- Grant privileges
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';

-- Additional security - limit to localhost only
GRANT USAGE ON *.* TO '$db_user'@'localhost' REQUIRE NONE WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;

FLUSH PRIVILEGES;
EOF
    fi
    
    # Test connection
    if mysql -u"$db_user" -p"$db_pass" -e "SELECT 1;" &>/dev/null; then
        debug "Database user can connect successfully"
    else
        error "Database user connection failed"
        return 1
    fi
}

optimize_mariadb_config() {
    info "Optimizing MariaDB for WordPress..."
    
    # Detect system resources
    eval "$(get_system_info)"
    
    # Calculate optimal settings
    local innodb_buffer_pool_size
    local max_connections
    local query_cache_size
    
    if [ "$TOTAL_MEM" -lt 1024 ]; then
        # Low memory system
        innodb_buffer_pool_size="128M"
        max_connections="50"
        query_cache_size="16M"
    elif [ "$TOTAL_MEM" -lt 4096 ]; then
        # Medium memory system
        innodb_buffer_pool_size="512M"
        max_connections="100"
        query_cache_size="32M"
    else
        # High memory system
        innodb_buffer_pool_size="1G"
        max_connections="200"
        query_cache_size="64M"
    fi
    
    # Create WordPress-specific configuration
    sudo tee /etc/mysql/mariadb.conf.d/60-wordpress-optimized.cnf >/dev/null <<EOF
[mysqld]
# WordPress Optimizations
# Generated by setup-wordpress.sh

# Basic Settings
max_connections = $max_connections
connect_timeout = 10
wait_timeout = 600
max_allowed_packet = 64M
thread_cache_size = 128
sort_buffer_size = 4M
bulk_insert_buffer_size = 16M
tmp_table_size = 32M
max_heap_table_size = 32M

# MyISAM Settings
myisam_recover_options = BACKUP
key_buffer_size = 32M
table_open_cache = 400
myisam_sort_buffer_size = 64M
concurrent_insert = 2
read_buffer_size = 2M
read_rnd_buffer_size = 1M

# Query Cache
query_cache_limit = 2M
query_cache_size = $query_cache_size
query_cache_type = 1

# InnoDB Settings
innodb_buffer_pool_size = $innodb_buffer_pool_size
innodb_log_file_size = 64M
innodb_buffer_pool_instances = 1
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_open_files = 400
innodb_io_capacity = 2000
innodb_read_io_threads = 4
innodb_write_io_threads = 4

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 2

# Character Set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_520_ci

[mysql]
default-character-set = utf8mb4

[client]
default-character-set = utf8mb4
EOF
    
    # Restart MariaDB to apply changes
    restart_service "mariadb"
    
    debug "MariaDB optimized for WordPress"
}

setup_database_backups() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    info "Setting up database backup system..."
    debug "Starting database backup setup for user: $db_user"
    
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    local backup_dir="/home/$backup_user/db-backups"
    debug "Using backup user: $backup_user, backup dir: $backup_dir"
    
    # Create backup directory
    debug "Creating backup directory..."
    sudo mkdir -p "$backup_dir"
    sudo chown "$backup_user:$backup_user" "$backup_dir"
    sudo chmod 750 "$backup_dir"
    debug "Backup directory created and configured"
    
    # Create backup credentials file
    debug "Creating backup credentials file..."
    local backup_creds="/home/$backup_user/.my.cnf"
    sudo tee "$backup_creds" >/dev/null <<EOF
[mysqldump]
user=$db_user
password=$db_pass
EOF
    
    sudo chown "$backup_user:$backup_user" "$backup_creds"
    sudo chmod 600 "$backup_creds"
    debug "Backup credentials file created"
    
    # Create backup script with proper variable expansion
    debug "Creating backup script..."
    local backup_script="/home/$backup_user/backup-database.sh"
    
    # Use double quotes to allow variable expansion
    sudo tee "$backup_script" >/dev/null <<EOF
#!/bin/bash
# Database backup script

DB_NAME="$db_name"
BACKUP_DIR="$backup_dir"
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/db_\${DB_NAME}_\${DATE}.sql.gz"

# Create backup
mysqldump --defaults-file=\$HOME/.my.cnf \\
    --single-transaction \\
    --routines \\
    --triggers \\
    --events \\
    "\$DB_NAME" | gzip > "\$BACKUP_FILE"

# Keep only last 7 days of backups
find "\$BACKUP_DIR" -name "db_\${DB_NAME}_*.sql.gz" -mtime +7 -delete

# Output backup file path for remote backup system
echo "\$BACKUP_FILE"
EOF
    
    sudo chown "$backup_user:$backup_user" "$backup_script"
    sudo chmod 750 "$backup_script"
    debug "Backup script created and configured"
    
    # Create cron job for daily backups
    info "Setting up daily backup cron job..."
    local cron_job="0 3 * * * /home/$backup_user/backup-database.sh >/dev/null 2>&1"
    
    # Create temporary file for cron job
    local temp_cron="/tmp/cron_${backup_user}_$$"
    
    # Get existing cron jobs (if any)
    sudo crontab -u "$backup_user" -l 2>/dev/null > "$temp_cron" || true
    
    # Add new cron job if it doesn't exist
    if ! grep -q "backup-database.sh" "$temp_cron" 2>/dev/null; then
        echo "$cron_job" >> "$temp_cron"
        if sudo crontab -u "$backup_user" "$temp_cron"; then
            debug "Cron job added successfully"
        else
            warning "Failed to add cron job, but continuing..."
        fi
    else
        debug "Cron job already exists"
    fi
    
    # Clean up temporary file
    rm -f "$temp_cron"
    
    debug "Database backup system configured"
}

verify_database_setup() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    info "Verifying database setup..."
    local all_good=true
    
    # Check if database exists
    if ! sudo mysql --defaults-file=/etc/mysql/debian.cnf -e "USE \`$db_name\`;" 2>/dev/null; then
        error "Database does not exist: $db_name"
        all_good=false
    fi
    
    # Check user privileges
    local privs=$(mysql -u"$db_user" -p"$db_pass" -e "SHOW GRANTS FOR CURRENT_USER;" 2>/dev/null)
    if [[ ! "$privs" =~ "ALL PRIVILEGES ON \`$db_name\`" ]]; then
        error "User privileges incorrect for: $db_user"
        all_good=false
    fi
    
    # Check charset
    local charset=$(sudo mysql --defaults-file=/etc/mysql/debian.cnf -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db_name';" -sN)
    if [ "$charset" != "utf8mb4" ]; then
        warning "Database charset is $charset, expected utf8mb4"
    fi
    
    # Check MariaDB optimization
    if [ ! -f "/etc/mysql/mariadb.conf.d/60-wordpress-optimized.cnf" ]; then
        error "MariaDB optimization config missing"
        all_good=false
    fi
    
    if ! $all_good; then
        error "Database verification failed"
        return 1
    fi
    
    success "Database verification passed"
}

# Database management functions
create_database_backup() {
    local db_name=$(load_state "DB_NAME")
    local backup_user=$(load_state "BACKUP_USER" "wp-backup")
    
    info "Creating database backup..."
    
    if sudo -u "$backup_user" /home/"$backup_user"/backup-database.sh; then
        success "Database backed up successfully"
    else
        error "Database backup failed"
        return 1
    fi
}

restore_database_backup() {
    local backup_file=$1
    local db_name=$(load_state "DB_NAME")
    local db_user=$(load_state "DB_USER")
    local db_pass=$(load_state "DB_PASS")
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    info "Restoring database from backup..."
    
    # Create database if not exists
    sudo mysql --defaults-file=/etc/mysql/debian.cnf -e "CREATE DATABASE IF NOT EXISTS \`$db_name\`;"
    
    # Restore based on file type
    if [[ "$backup_file" =~ \.gz$ ]]; then
        gunzip -c "$backup_file" | mysql -u"$db_user" -p"$db_pass" "$db_name"
    else
        mysql -u"$db_user" -p"$db_pass" "$db_name" < "$backup_file"
    fi
    
    if [ $? -eq 0 ]; then
        success "Database restored successfully"
    else
        error "Database restore failed"
        return 1
    fi
}

# Cleanup function
cleanup_database() {
    if ! confirm "Remove WordPress database and user? This cannot be undone!" N; then
        return 1
    fi
    
    local db_name=$(load_state "DB_NAME")
    local db_user=$(load_state "DB_USER")
    
    info "Removing database and user..."
    
    sudo mysql --defaults-file=/etc/mysql/debian.cnf <<EOF
DROP DATABASE IF EXISTS \`$db_name\`;
DROP USER IF EXISTS '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    warning "Database removed: $db_name"
}

debug "Database module loaded successfully"
