# Codebase Map

> **Quick navigation guide - "What file does what?"**

---

## Directory Structure

```
VPS2/
├── .claude/
│   ├── skills/              # Canonical workflow skills (Claude + Codex)
│   │   ├── check-reviews    # Detect unaddressed reviews (run first!)
│   │   ├── address-review   # Address review feedback
│   │   ├── claim-issue      # Claim issue + create branch
│   │   ├── check-workflow   # Validate workflow state
│   │   ├── submit-pr        # Create PR + update labels
│   │   └── README.md        # Skills documentation
│   ├── commands/            # Command documentation
│   └── SECURITY-CHECKLIST.md
├── .codex/
│   └── skills -> ../.claude/skills  # Codex mirror (symlink)
│
├── docs/                    # Documentation
│   ├── QUICK-REFERENCE.md   # Navigation hub
│   ├── FAQ-AGENTS.md        # Common questions
│   └── CODEBASE-MAP.md      # This file
│
├── wordpress-mgmt/
│   └── lib/                 # Module libraries (downloaded from GitHub)
│       ├── utils.sh         # Foundation (logging, validation, permissions)
│       ├── preflight.sh     # System checks (7-point validation)
│       ├── packages.sh      # Dependency installation
│       ├── config.sh        # Interactive configuration
│       ├── users.sh         # Multi-user security model
│       ├── sftp.sh          # Chrooted SFTP access
│       ├── database.sh      # MariaDB setup & management
│       ├── nginx.sh         # Web server + PHP-FPM pools
│       ├── wordpress.sh     # WP installation & management
│       ├── ssl.sh           # Certificate management
│       ├── security.sh      # Fail2ban, UFW, hardening
│       └── backup.sh        # Automated backup system
│
├── setup-wordpress.sh       # Main orchestrator (38 KB)
├── vps-setup.sh             # Initial VPS provisioning
├── wp-security-audit.sh     # Security assessment tool
├── vps-maint-rep.sh         # Maintenance reporting
│
├── AGENTS.md                # Comprehensive agent guide
├── GEMINI.md                # Gemini-specific documentation
└── README.md                # Project overview
```

---

## Key Entry Points

### Main Scripts
| Script | Purpose | Size |
|--------|---------|------|
| `setup-wordpress.sh` | Main orchestrator - fresh installs, imports, restorations | 38 KB |
| `vps-setup.sh` | Initial VPS provisioning (WIP) | 3.7 KB |
| `wp-security-audit.sh` | Security assessment & malware detection | 19 KB |

### Workflow Commands
| Command | Purpose | Location |
|---------|---------|----------|
| `/check-reviews` | Detect unaddressed reviews | `.claude/skills/check-reviews` |
| `/address-review` | Address review feedback | `.claude/skills/address-review` |
| `/claim-issue` | Claim GitHub issue | `.claude/skills/claim-issue` |
| `/check-workflow` | Validate labels | `.claude/skills/check-workflow` |
| `/submit-pr` | Create pull request | `.claude/skills/submit-pr` |

### Development Commands
| Command | Purpose |
|---------|---------|
| `shellcheck *.sh` | Run linting/tests |
| `shellcheck wordpress-mgmt/lib/*.sh` | Check module libraries |

---

## Quick Lookup by Task

### "I need to modify WordPress installation logic"
- Core installation: `wordpress-mgmt/lib/wordpress.sh`
- Configuration: `wordpress-mgmt/lib/config.sh`
- Main orchestrator: `setup-wordpress.sh`

### "I need to modify backup behavior"
- Backup system: `wordpress-mgmt/lib/backup.sh`
- Backup location: `/home/wp-backup/backups/`

### "I need to modify permissions"
- Permission model: `wordpress-mgmt/lib/utils.sh` → `enforce_standard_permissions()`
- Security hardening: `wordpress-mgmt/lib/security.sh`

### "I need to modify nginx configuration"
- Nginx setup: `wordpress-mgmt/lib/nginx.sh`
- SSL certificates: `wordpress-mgmt/lib/ssl.sh`

### "I need to modify database operations"
- Database setup: `wordpress-mgmt/lib/database.sh`

### "I need to write tests"
- Test command: `shellcheck *.sh`
- No formal test directory exists yet

### "I need to update documentation"
- Agent documentation: `AGENTS.md`
- Quick reference: `docs/QUICK-REFERENCE.md`
- FAQ: `docs/FAQ-AGENTS.md`
- Skills documentation: `.claude/skills/README.md`

---

## File Naming Conventions

- **Scripts:** `kebab-case.sh`
- **Libraries:** `snake_case.sh` (in lib/)
- **Documentation:** `SCREAMING-CASE.md`
- **Config files:** `lowercase.json`

---

## Dependencies

### External Services
- GitHub: Module updates, self-updating, SSH key retrieval
- WordPress.org: Core downloads, salt/key generation
- Let's Encrypt: SSL certificates via certbot
- Cloudflare: Origin CA certificates, WAF integration
- Sury PHP Repository: PHP 8.3+ packages

### System Services
- nginx: Web server with per-site PHP-FPM pools
- MariaDB: Database server
- Redis: Optional object cache
- fail2ban: Intrusion prevention
- UFW: Firewall management

---

## Common Patterns

### State Management
```bash
# Check state before operations
if state_exists "OPERATION_COMPLETED"; then
    log_info "Already completed, skipping..."
    return 0
fi

# Save state after completion
save_state "OPERATION_COMPLETED" "true"
```

### Error Handling
```bash
function_name() {
    log_info "Starting operation..."

    if ! validate_preconditions; then
        log_error "Validation failed"
        return 1
    fi

    if ! perform_operation; then
        log_error "Operation failed"
        return 1
    fi

    log_success "Operation completed"
    return 0
}
```

---

## Related Documentation

- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Fast navigation
- [FAQ-AGENTS.md](FAQ-AGENTS.md) - Common questions
- [.claude/skills/README.md](../.claude/skills/README.md) - Workflow skills (mirrored at `.codex/skills`)
- [AGENTS.md](../AGENTS.md) - Complete architecture guide

---

**Maintenance Note:**

Keep this document updated when:
- Adding new directories
- Moving files
- Changing project structure

---

**Last updated:** 2026-01-12
