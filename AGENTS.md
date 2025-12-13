# AGENTS.md - AI Agent Guide for WordPress VPS Management System

## System Overview

This is an **enterprise-grade WordPress VPS management system** that automates the deployment, configuration, security hardening, and maintenance of WordPress installations on Linux VPS servers. The system is production-ready and manages multiple client installations across different servers.

**Primary Purpose:** Standardized, secure, automated WordPress environment deployment with multi-server support, backup management, security hardening, and site migration capabilities.

**Current Version:** 3.1.4 (self-updating from GitHub)

**Target Environment:** Ubuntu 20.04+ / Debian 11+

---

## Architecture Overview

### Core Entry Points

1. **`setup-wordpress.sh`** (38 KB) - Main orchestrator
   - Fresh installations, imports, restorations
   - State-driven execution with resume capability
   - Menu-based interface for all operations
   - Self-updating from GitHub

2. **`vps-setup.sh`** (3.7 KB) - Initial VPS provisioning
   - First-time server setup
   - SSH hardening, firewall, user creation
   - Development status (work-in-progress)

3. **`wp-security-audit.sh`** (19 KB) - Security assessment
   - Standalone security auditor
   - Malware detection, plugin analysis
   - Self-updating capability

### Modular Library System

**Location:** `wordpress-mgmt/lib/` (downloaded from GitHub on-demand)

```
setup-wordpress.sh
    ↓ Downloads & loads modules
wordpress-mgmt/lib/
    ├── utils.sh         ← Foundation (logging, validation, permissions)
    ├── preflight.sh     ← System checks (7-point validation)
    ├── packages.sh      ← Dependency installation (PHP 8.3+, nginx, MariaDB)
    ├── config.sh        ← Interactive configuration gathering
    ├── users.sh         ← Multi-user security model
    ├── sftp.sh          ← Chrooted SFTP access
    ├── database.sh      ← MariaDB setup & management
    ├── nginx.sh         ← Web server + PHP-FPM pools
    ├── wordpress.sh     ← WP installation & management
    ├── ssl.sh           ← Certificate management (Let's Encrypt, Cloudflare CA)
    ├── security.sh      ← Fail2ban, UFW, hardening
    └── backup.sh        ← Automated backup system
```

**Dependency Chain:** `utils.sh` is required by all modules. Load order matters for state management.

---

## Key Concepts for AI Agents

### 1. State Management System

**Critical File:** `wordpress-mgmt/setup_state`

The system uses **persistent state** to enable:
- Resume capability after failures
- Idempotent operations
- Step-by-step re-runs
- Configuration persistence

**State Functions (in setup-wordpress.sh):**
```bash
state_exists "KEY"           # Check if key exists
save_state "KEY" "value"     # Save/update state
load_state "KEY" "default"   # Load with fallback
remove_state "KEY"           # Delete entry
```

**Important State Variables:**
- `PREFLIGHT_COMPLETED`, `PACKAGES_INSTALLED`, `CONFIG_COMPLETED`
- `DOMAIN`, `WP_ROOT`, `ADMIN_EMAIL`, `DB_NAME`, `DB_USER`, `DB_PASS`
- `PHP_VERSION`, `SSL_TYPE`, `WAF_TYPE`
- `ENABLE_SFTP`, `ENABLE_REDIS`, `SFTP_WHITELIST_IPS`

**When making changes:**
- Always check if state exists before operations
- Save state after successful completion of major steps
- Never assume state values - always use `load_state` with defaults

### 2. Security Model - Multi-User Isolation

**Critical Concept:** Service isolation through dedicated users and groups.

**User Architecture:**
```
wpuser       ← WordPress file owner (no login)
php-fpm      ← PHP execution context
redis        ← Redis cache service
wp-backup    ← Backup operations (SSH key auth)
wp-sftp      ← SFTP uploads (chrooted)
```

**Group Membership:**
- `wordpress` group: wpuser, php-fpm, wp-backup (shared access)
- `web` group: php-fpm, www-data (web server coordination)
- `sftp-users` group: wp-sftp (chroot matching)

**NEVER:**
- Give wpuser a password or shell access
- Run WordPress as www-data or root
- Use 777 permissions (always use standardized model)
- Mix service user contexts

### 3. Standardized Permission Model

**Critical Function:** `enforce_standard_permissions()` in `utils.sh`

**Permission Standards:**
```
644  ← Readable files (PHP, CSS, JS, images)
755  ← Directories and executables
640  ← Sensitive config (wp-config.php) - wpuser:wordpress
2775 ← Writable directories (uploads, cache) - php-fpm:wordpress (setgid)
2750 ← Backup/log directories (setgid + group read)
```

**Setgid (2xxx) Benefits:**
- Preserves group ownership on new files
- Enables service coordination without sudo
- Critical for backup operations

**When modifying permissions:**
- Always use `enforce_standard_permissions()` function
- Never hardcode permission values in new code
- Test with backup user after changes

### 4. PHP Version Management

**Critical:** System auto-detects and upgrades PHP (8.3+ required)

**Key Functions in utils.sh:**
- `get_php_version()` - Detects installed version
- `get_php_service()` - Returns service name (php8.3-fpm, php8.4-fpm)
- `get_php_fpm_pool_dir()` - Returns pool config directory
- `update_php_version()` - In-place PHP upgrades

**When adding PHP-related features:**
- Never hardcode PHP version (use functions)
- Always use version-agnostic socket symlink: `/run/php/php-fpm-wpuser_pool.sock`
- Test across PHP 8.3 and 8.4

### 5. Modular Function Pattern

**Standard Pattern for New Features:**
```bash
function_name() {
    log_info "Starting operation..."

    # Validation
    if ! validate_preconditions; then
        log_error "Validation failed"
        return 1
    fi

    # Main logic with error handling
    if ! perform_operation; then
        log_error "Operation failed"
        return 1
    fi

    # State persistence
    save_state "OPERATION_COMPLETED" "true"
    log_success "Operation completed successfully"
    return 0
}
```

**Key Patterns:**
- Always return 0 on success, 1 on failure
- Use logging functions (log_info, log_success, log_warning, log_error)
- Save state after successful completion
- Include validation before destructive operations
- Use `confirm()` for user confirmation on risky operations

### 6. Backup System Architecture

**Location:** `/home/wp-backup/backups/`

**Structure:**
```
backups/
├── daily/    ← Mon-Sat backups (configurable retention)
├── weekly/   ← Sunday backups
└── monthly/  ← 1st of month backups
```

**Backup Contents:**
- Database dump (with routines, triggers, events)
- wp-config.php
- wp-content/ (excluding cache, backups, upgrade, wflogs)
- SHA256 checksums for integrity

**Retention Logic:**
- Configurable count (default: 2 per tier)
- Pinned backups (prevent deletion)
- Recent performance optimization: rclone 25x speedup (56s → 2s)

**When modifying backup logic:**
- Test retention logic thoroughly
- Never delete pinned backups
- Maintain SHA256 checksums
- Verify database dump includes routines/triggers

### 7. WAF/Proxy Integration

**Supported WAF Types:**
- Cloudflare (with Origin CA support)
- Sucuri WAF
- BunkerWeb
- Custom upstream proxy

**Critical Files:**
- `config.sh` - WAF type selection
- `nginx.sh` - WAF-specific nginx configuration
- `ssl.sh` - Cloudflare Origin CA certificate handling

**When behind WAF:**
- Use appropriate SSL type (Cloudflare Origin CA for Cloudflare)
- Configure nginx for real IP detection
- Adjust fail2ban actions (firewall-cmd vs direct iptables)

---

## Critical Files Reference

### setup-wordpress.sh (Main Orchestrator)
**Key Functions:**
- `download_and_load_modules()` - Module management
- `state_exists()`, `save_state()`, `load_state()` - State management
- `run_fresh_installation()` - Fresh install workflow
- `run_import_wordpress()` - Site migration workflow
- `resume_from_last_step()` - Resume capability
- `utils_menu()` - Maintenance operations

**When to modify:**
- Adding new menu options
- Adding new installation workflows
- Changing state management logic
- Adding new modules

### lib/utils.sh (Foundation Layer)
**Key Functions:**
- `log_info()`, `log_success()`, `log_warning()`, `log_error()` - Logging
- `enforce_standard_permissions()` - **CRITICAL** permission model
- `verify_wordpress_stack()` - 6-point system verification
- `get_php_version()`, `get_php_service()` - PHP version detection
- `generate_password()` - Secure password generation (24 chars)
- `confirm()`, `get_input()` - User interaction

**When to modify:**
- Adding new utility functions used across modules
- Changing logging format
- Modifying permission model (CAREFUL!)
- Adding new validation functions

### lib/wordpress.sh (WordPress Operations)
**Key Functions:**
- `download_wordpress()` - WP core download
- `configure_wordpress()` - wp-config.php generation
- `install_wordpress()` - WP installation via WP-CLI
- `import_wordpress_site()` - Site migration with multiple import methods
- `verify_wordpress_installation()` - Installation validation

**Recent Changes:**
- Added support for additional non-standard folders in imports
- UTF-8 encoding fixes for bash scripts
- WordPress Site Health REST API fixes

**When to modify:**
- Adding new import sources
- Changing default plugins
- Modifying wp-config.php generation
- Adding WordPress-specific features

### lib/backup.sh (Backup System)
**Key Functions:**
- `setup_backup_system()` - Initial backup configuration
- `perform_backup()` - Execute backup operation
- `cleanup_old_backups()` - Retention enforcement
- `restore_from_backup()` - Restoration workflow

**Recent Changes:**
- Fixed retention logic issues
- Added pinned backup support
- rclone performance optimization (128MB chunks, increased buffers)

**When to modify:**
- Changing retention logic
- Adding backup destinations (S3, etc.)
- Modifying backup contents
- Adding encryption

### lib/security.sh (Security Hardening)
**Key Functions:**
- `configure_fail2ban()` - Intrusion prevention
- `configure_firewall()` - UFW setup
- `harden_file_permissions()` - Permission enforcement
- `generate_security_report()` - Security assessment

**When to modify:**
- Adding new fail2ban filters
- Changing ban policies
- Adding new security checks
- Modifying firewall rules

---

## Development Principles

### 1. Manual First, Automate Later
- Implement changes manually first to understand implications
- Test thoroughly before scripting
- Verify on production-like systems before deployment

### 2. Backward Compatibility
- Existing installations must continue functioning
- State migration for breaking changes
- Graceful degradation where possible
- Never remove state variables without migration path

### 3. Security-First
- No 777 permissions ever
- No passwords in logs
- Validate all user input
- Use service-specific users
- Enable security features by default

### 4. Error Handling
- Always check command return codes
- Provide clear error messages
- Include diagnostic information
- Enable recovery paths

### 5. Logging & Debugging
- Use consistent logging functions
- Include context in log messages
- Support DEBUG=1 for verbose output
- Log to file (setup.log) for troubleshooting

### 6. Testing Approach
- "Nuke and rebuild" testing cycles
- Test across PHP 8.3 and 8.4
- Test with different WAF configurations
- Verify backup/restore workflows
- Test permission enforcement

---

## Common Tasks for AI Agents

### Adding a New Feature Module

1. Create `lib/new-feature.sh` with standard structure
2. Add source line to `setup-wordpress.sh` module loading
3. Add state variables (e.g., `NEW_FEATURE_CONFIGURED`)
4. Add menu option if needed
5. Update this AGENTS.md with new module details

### Modifying Permissions

**NEVER modify permissions directly**
- Update `enforce_standard_permissions()` in `lib/utils.sh`
- Test with all user contexts (wpuser, php-fpm, wp-backup)
- Verify backup operations still work
- Test SFTP access if applicable

### Adding New Configuration Options

1. Add to `config.sh` interactive gathering
2. Save to state: `save_state "NEW_OPTION" "$value"`
3. Load in relevant module: `NEW_OPTION=$(load_state "NEW_OPTION" "default")`
4. Update resume logic if needed

### Debugging Issues

1. Check `wordpress-mgmt/setup.log` for detailed logs
2. Run with `DEBUG=1` for verbose output
3. Verify state file contents: `cat wordpress-mgmt/setup_state`
4. Check permissions: `ls -la /var/www/wordpress`
5. Verify user/group memberships: `groups wpuser php-fpm wp-backup`
6. Test services: `systemctl status php8.3-fpm nginx mariadb redis-server`

### Security Considerations

**Before making changes:**
- Review multi-user isolation model impact
- Check permission implications
- Verify no privilege escalation paths
- Test with restricted users (wp-backup, wp-sftp)
- Ensure no passwords in logs or state files

**Security checklist:**
- [ ] No hardcoded passwords
- [ ] No 777 permissions
- [ ] No sudo without restrictions
- [ ] Input validation on user-provided data
- [ ] Error messages don't reveal sensitive info
- [ ] Services run as dedicated users

---

## Performance Considerations

### Recent Optimizations

1. **rclone Upload Performance** (25x improvement)
   - Changed chunk size: 8MB → 128MB
   - Increased buffer size and transfers
   - Result: 56s → 2s for test files

2. **Backup Retention Logic**
   - Fixed excessive deletions
   - Optimized find operations
   - Proper sorting and limiting

### When adding features:

- Prefer `find` over `ls` for file operations (reliability)
- Use WP-CLI for WordPress operations (efficiency)
- Consider caching for expensive operations
- Test performance impact on low-memory systems (<512MB)

---

## Integration Points

### External Services
- **GitHub:** Module updates, self-updating, SSH key retrieval
- **WordPress.org:** Core downloads, salt/key generation
- **Let's Encrypt:** SSL certificates via certbot
- **Cloudflare:** Origin CA certificates, WAF integration
- **Sury PHP Repository:** PHP 8.3+ packages

### System Services
- **nginx:** Web server with per-site PHP-FPM pools
- **MariaDB:** Database server with WordPress-optimized config
- **Redis:** Optional object cache
- **fail2ban:** Intrusion prevention with WordPress filters
- **UFW:** Firewall management
- **inotify-tools:** SFTP file monitoring

---

## Error Recovery Patterns

### Resume Capability
The system can resume from failures using state:
```bash
sudo ./setup-wordpress.sh
# Select: Resume/Re-run Menu → Resume from last failed step
```

### Re-run Specific Steps
```bash
sudo ./setup-wordpress.sh
# Select: Resume/Re-run Menu → Re-run specific step
# Choose: preflight, packages, database, nginx, ssl, security, backup
```

### Nuke and Rebuild
For complete reset preserving state:
```bash
sudo ./setup-wordpress.sh
# Select: Utils Menu → Remove WordPress (Nuke System)
# Then: Fresh installation with same config
```

---

## Current Known Limitations

1. **vps-setup.sh** - Development status, not fully integrated
2. **Multi-site WordPress** - Not yet supported
3. **Database clustering** - Single MariaDB instance only
4. **Backup encryption** - Not yet implemented (ready to add)
5. **Cloudflare API integration** - Manual cert handling (API automation possible)
6. **Documentation gap** - Current capabilities exceed existing docs (this file addresses that)

---

## Roadmap Items (Per Project Memory)

### High Priority
1. Convert custom PHP scripts to proper WordPress plugins
2. Integrate phpMyAdmin access management
3. Complete vps-setup.sh development
4. Backup encryption implementation

### Medium Priority
1. WAF configuration guides
2. Architecture documentation
3. Security model documentation
4. Multi-site WordPress support

### Low Priority
1. Database clustering support
2. Cloudflare API automation
3. Advanced caching (FastCGI)
4. Monitoring integration (Prometheus/Grafana)

---

## Testing Checklist for Changes

Before committing changes, verify:

- [ ] Fresh installation works (full workflow)
- [ ] Resume from failure works
- [ ] Permissions are correct (run `ls -la /var/www/wordpress`)
- [ ] Backup operation succeeds (test as wp-backup user)
- [ ] No passwords in logs or output
- [ ] State file updated correctly
- [ ] Works with PHP 8.3 and 8.4
- [ ] SFTP access works (if enabled)
- [ ] Fail2ban rules active (check `fail2ban-client status`)
- [ ] SSL certificate generation succeeds
- [ ] WordPress Site Health shows no critical issues
- [ ] No UTF-8 encoding issues in bash scripts

---

## Contact & Repository

**GitHub Repository:** wordpress-mgmt scripts (auto-downloaded from GitHub)

**Maintainer:** ait88

**Development Branch:** `claude/create-agents-documentation-01VR9Wbd46MVMe8DiXeemaoB`

---

## Quick Reference

### Most Important Files
1. `setup-wordpress.sh` - Main entry point
2. `lib/utils.sh` - Foundation functions
3. `lib/wordpress.sh` - WordPress operations
4. `lib/backup.sh` - Backup system
5. `lib/security.sh` - Security hardening
6. `wordpress-mgmt/setup_state` - State persistence

### Most Important Functions
1. `enforce_standard_permissions()` - Permission model
2. `verify_wordpress_stack()` - System verification
3. `save_state()` / `load_state()` - State management
4. `log_*()` - Logging functions
5. `confirm()` - User confirmation

### Most Important Concepts
1. **Multi-user isolation** - Service-specific users
2. **State-driven execution** - Resume capability
3. **Standardized permissions** - 644/755/640/2775/2750 model
4. **Modular architecture** - Separate libraries
5. **Security-first** - Multiple hardening layers

---

## Final Notes for AI Agents

**When working with this codebase:**

1. **Always read existing code before modifying** - Don't assume, verify
2. **Test thoroughly** - This is production infrastructure
3. **Preserve backward compatibility** - Existing installations must work
4. **Follow established patterns** - Consistency is critical
5. **Document changes** - Update this file when adding features
6. **Security first** - When in doubt, be more restrictive
7. **Ask before destructive changes** - Especially permission model changes

**This system is production-critical infrastructure managing real client sites. Proceed with care and thorough testing.**

---

*Document Version: 1.0*
*Last Updated: 2025-12-13*
*Codebase Version: 3.1.4*
