# VPS Setup Script

This script automates the initial setup of a VPS running Ubuntu. It creates a secure user, configures SSH access, applies security best practices, and installs essential packages.

## Features

- Creates a new sysadmin user with sudo privileges
- Sets up SSH key authentication
- Configures UFW to restrict access
- Enforces password complexity requirements
- Hardens SSH configuration
- Installs Fail2Ban for security
- Fetches a custom `.bashrc` configuration from GitHub
- Enables automatic security updates

## Prerequisites

- A fresh Ubuntu VPS
- Root access to execute the script
- A GitHub account with an SSH key uploaded

## Optional: Only update `.bashrc` with single command.
   
   ```bash
   curl -sL https://raw.githubusercontent.com/ait88/VPS/main/.bashrc -o ~/.bashrc && exec bash
   ```

## Usage

1. SSH into your VPS as root:
   ```bash
   ssh root@your-vps-ip
   ```
2. Download the setup script:
   ```bash
   curl -sL https://raw.githubusercontent.com/ait88/VPS/main/vps-setup.sh -o vps-setup.sh
   ```
3. Make the script executable:
   ```bash
   chmod +x vps-setup.sh
   ```
4. Run the script with sudo:
   ```bash
   sudo ./vps-setup.sh
   ```
5. Follow the prompts to set up your username, allowed IP, and GitHub username.

## Post-Installation

- Log in with your new user:
  ```bash
  ssh sysadmin@your-vps-ip
  ```
- Verify that SSH key authentication is working.
- Ensure your firewall (UFW) is properly configured.
- Check Fail2Ban status:
  ```bash
  sudo systemctl status fail2ban
  ```

## Notes

- Password authentication for SSH is disabled after setup.
- The default SSH port remains **22** (can be changed in `sshd_config`).
- The `.bashrc` configuration is fetched from `https://raw.githubusercontent.com/ait88/VPS/main/.bashrc`.

## Troubleshooting

- If you get locked out, use your VPS provider's console to regain access.
- Ensure your GitHub SSH key is correctly set up:
  ```bash
  curl -s https://github.com/YOUR_GITHUB_USERNAME.keys
  ```
- Check firewall rules:
  ```bash
  sudo ufw status
  ```

## License

This script is provided as-is without warranty. Modify and use it at your own risk.

