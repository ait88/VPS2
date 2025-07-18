# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

## User Notes
- The goal of this project is to have the all the functionality and features of the standardised VPS, Wordpress, backup and monitoring environment be easily manage via the management scripts. 
- When probems arise, the solution is to update the scripts to handle the problem, configurations that don't conform to the standard environment can be removed.
- Check the flow of opperations, watch out for place holder files/operations that need fleshing out.
- Periodically, suggest important notes or information that should be documented in this file or README.md
- Don't forget to commit and push changes to the origin main repo

## Claude's Notes
- I can add notes here for myself, Hi Claude! 

### Initial Setup
```bash
# VPS initialization and security configuration
sudo ./vps-setup.sh

# WordPress installation with security hardening
sudo ./setup-wordpress.sh

# WordPress security audit and assessment
./wp-security-audit.sh
```

### Menu System
The main setup script now includes organized menus:

**Installation Options (1-4):**
- Fresh WordPress installation
- Import existing WordPress site  
- Restore from backup
- Update modules

**Management Menus (6-9):**
- Utils Menu: Permissions fixer, domain change, nuke system
- Monitoring Menu: (Future: resource/uptime/security monitoring)
- Maintenance Menu: (Future: updates, optimization, cleanup)

### Utils Menu Features
```bash
# Access utils menu
./setup-wordpress.sh
# Choose option 6

# Available utils:
# 1) Fix/Enforce Standard Permissions
# 2) Change Primary Domain  
# 3) Remove WordPress (Nuke System)
```

### Development and Testing
```bash
# Test individual library modules
bash -x wordpress-mgmt/lib/utils.sh
bash -x wordpress-mgmt/lib/preflight.sh

# Check script syntax
bash -n script_name.sh

# Run security audit on WordPress installations
./wp-security-audit.sh /var/www/wordpress

# Apply standardized permissions (from utils.sh)
source wordpress-mgmt/lib/utils.sh
enforce_standard_permissions
```

### State Management
```bash
# View current setup state
cat wordpress-mgmt/setup_state

# View setup logs
tail -f wordpress-mgmt/setup.log

# Reset state (for testing)
rm -f wordpress-mgmt/setup_state
```

## Architecture Overview

This is a **modular WordPress deployment and VPS management system** with enterprise-grade security and performance optimization. The architecture follows a library-based design with clear separation of concerns.

### Core Components

**Main Scripts:**
- `setup-wordpress.sh` - Orchestrates WordPress installation with self-updating and state management
- `vps-setup.sh` - Initial VPS setup with security hardening
- `wp-security-audit.sh` - Security assessment and vulnerability scanning

**Modular Library System (wordpress-mgmt/lib/):**
- `utils.sh` - Foundation utilities (logging, validation, system info)
- `preflight.sh` - System compatibility and resource checks
- `config.sh` - Interactive configuration system with WAF/proxy support
- `users.sh` - Multi-user security model with service isolation
- `database.sh` - MariaDB setup with performance optimization
- `nginx.sh` - Web server configuration with security headers
- `wordpress.sh` - WordPress installation and management via WP-CLI
- `ssl.sh` - SSL/TLS automation (Let's Encrypt, Cloudflare Origin CA)
- `security.sh` - Security hardening (fail2ban, firewall, file permissions)
- `backup.sh` - Multi-tier backup system with automated cleanup

### Key Architectural Patterns

**State-Driven Execution:**
- Configuration persisted in `wordpress-mgmt/setup_state`
- Resumable installations with `save_state()` and `load_state()`
- Conditional module loading based on saved state

**Security-First Design:**
- Multi-user isolation (wp-user, php-user, redis-user, backup-user)
- Least privilege principle with service account separation
- Defense in depth with automated security hardening

**Modular Dependencies:**
- All modules depend on `utils.sh` for foundation utilities
- `config.sh` drives configuration for all other modules
- Clear module interfaces with standardized logging and error handling

### Installation Modes

The system supports three installation modes:
1. **Fresh Install** - Clean WordPress installation
2. **Import Existing** - Migrate from existing WordPress site
3. **Restore from Backup** - Restore from backup files

### WAF/Proxy Integration

Built-in support for:
- Cloudflare (with Origin CA certificates)
- Sucuri WAF
- BunkerWeb
- Custom proxy configurations

### File Locations

- **Scripts:** `/home/sysadmin/VPS2/`
- **Libraries:** `/home/sysadmin/VPS2/wordpress-mgmt/lib/`
- **State:** `/home/sysadmin/VPS2/wordpress-mgmt/setup_state`
- **Logs:** `/home/sysadmin/VPS2/wordpress-mgmt/setup.log`
- **WordPress:** `/var/www/wordpress` (configurable)

When working with this codebase, always check the setup state and logs first, understand the modular library dependencies, and follow the existing patterns for logging and error handling.

## Permission Standards

The system implements a standardized security permission model:

### User/Group Structure
- **wpuser:wordpress** - WordPress file ownership and PHP-FPM access
- **php-fpm:wordpress** - PHP execution with WordPress group access  
- **www-data:wordpress** - Nginx web server read access
- **wp-backup:wordpress** - Read-only backup access

### Permission Model
- **644** - Readable files (PHP, CSS, JS, images)
- **755** - Directories and executable files
- **640** - Sensitive config files (wp-config.php)
- **2775** - Writable directories (setgid + group write)
- **2750** - Backup/log directories (setgid + group read)

### Critical Security Fixes Applied
1. wp-config.php uses **wordpress** group consistently (not php-fpm group)
2. Writable directories owned by **php-fpm:wordpress** with setgid
3. Backup user home directory owned by **wp-backup:wp-backup**
4. All WordPress files use **wordpress** group for consistent access

See `docs/sec_groups` for detailed permission reference.
