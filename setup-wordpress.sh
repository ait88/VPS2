#!/bin/bash
# setup-wordpress.sh - Modular WordPress installation with backup integration

# ===== CONFIGURATION SECTION =====
SCRIPT_VERSION="2.0"
STATE_FILE="/root/.wordpress_setup_state"
BACKUP_USER="wp-backup"
BACKUP_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKk1nsYyDbYzYL5UXEc8X9IDBIJECt9mQzy307M6h7p5"

# ===== STATE MANAGEMENT =====
load_state()
save_state()
check_existing_installation()

# ===== CORE MODULES =====
01_preflight_checks()
02_install_dependencies()
03_interactive_menu()
04_setup_users_and_permissions()
05_configure_mariadb()
06_configure_php_fpm()
07_configure_nginx()
08_setup_wordpress()
09_configure_security()
10_setup_backups()
11_configure_monitoring()
12_post_installation()

# ===== INSTALLATION MODES =====
mode_fresh_install()
mode_import_site()
mode_restore_backup()
mode_reconfigure()
mode_reset()

# ===== UTILITY FUNCTIONS =====
generate_secure_password()
validate_domain()
check_port_availability()
test_database_connection()
verify_backup_format()