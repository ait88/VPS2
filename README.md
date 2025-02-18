VPS Setup Script

This script automates the initial setup of a VPS running Ubuntu. It creates a secure user, configures SSH access, applies security best practices, and installs essential packages.

Features

Creates a new sysadmin user with sudo privileges

Sets up SSH key authentication

Configures UFW to restrict access

Enforces password complexity requirements

Hardens SSH configuration

Installs Fail2Ban for security

Fetches a custom .bashrc configuration from GitHub

Enables automatic security updates

Prerequisites

A fresh Ubuntu VPS

Root access to execute the script

A GitHub account with an SSH key uploaded

Usage

SSH into your VPS as root:

ssh root@your-vps-ip

Download the setup script:

curl -sL https://raw.githubusercontent.com/ait88/VPS/main/vps-setup.sh -o vps-setup.sh

Make the script executable:

chmod +x vps-setup.sh

Run the script with sudo:

sudo ./vps-setup.sh

Follow the prompts to set up your username, allowed IP, and GitHub username.

Post-Installation

Log in with your new user:

ssh sysadmin@your-vps-ip

Verify that SSH key authentication is working.

Ensure your firewall (UFW) is properly configured.

Check Fail2Ban status:

sudo systemctl status fail2ban

Notes

Password authentication for SSH is disabled after setup.

The default SSH port remains 22 (can be changed in sshd_config).

The .bashrc configuration is fetched from https://raw.githubusercontent.com/ait88/VPS/main/.bashrc.

Troubleshooting

If you get locked out, use your VPS provider's console to regain access.

Ensure your GitHub SSH key is correctly set up:

curl -s https://github.com/YOUR_GITHUB_USERNAME.keys

Check firewall rules:

sudo ufw status

License

This script is provided as-is without warranty. Modify and use it at your own risk.
