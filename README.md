# VPS2 - WordPress & VPS Management Tools

Modular scripts for WordPress deployment and VPS management.

## Quick Start

### WordPress Installation
```bash
curl -sL https://raw.githubusercontent.com/ait88/VPS2/main/setup-wordpress.sh -o setup-wordpress.sh
chmod +x setup-wordpress.sh
sudo ./setup-wordpress.sh
```

### VPS Initial Setup
```bash
curl -sL https://raw.githubusercontent.com/ait88/VPS2/main/vps-setup.sh -o vps-setup.sh
chmod +x vps-setup.sh
sudo ./vps-setup.sh
```

### WordPress Security Audit
```bash
curl -sL https://raw.githubusercontent.com/ait88/VPS2/main/wp-security-audit.sh -o wp-security-audit.sh
chmod +x wp-security-audit.sh
./wp-security-audit.sh
```

## Tools

- **setup-wordpress.sh** - Complete WordPress installation with security hardening
- **vps-setup.sh** - VPS initialization and security configuration  
- **wp-security-audit.sh** - WordPress security assessment tool

## Shell Customizations

For `.bashrc` updates and shell customizations, see the [original VPS repository](https://github.com/ait88/VPS).

```bash
# Update .bashrc from original repo
curl -sL https://raw.githubusercontent.com/ait88/VPS/main/.bashrc -o ~/.bashrc && exec bash
```
