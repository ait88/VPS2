
## Update `.bashrc` with single command.
   
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
