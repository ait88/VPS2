#!/bin/bash

# Prompt for user input
read -p "Enter sysadmin username: " SYSADMIN_USER
read -p "Enter allowed IP for SSH access: " ALLOWED_IP
read -p "Enter GitHub username for SSH key retrieval: " GITHUB_USERNAME
SSH_PORT=22

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Update system
echo "Updating system..."
apt update && apt upgrade -y

# Create sysadmin user if it doesn't exist
if ! id "$SYSADMIN_USER" &>/dev/null; then
    echo "Creating user $SYSADMIN_USER..."
    adduser --disabled-password --gecos "" $SYSADMIN_USER
    usermod -aG sudo $SYSADMIN_USER
fi

# Allow SSH access
mkdir -p /home/$SYSADMIN_USER/.ssh
chmod 700 /home/$SYSADMIN_USER/.ssh

# Configure SSH key authentication
echo "Setting up SSH Key Authentication..."
curl -s https://github.com/$GITHUB_USERNAME.keys > /home/$SYSADMIN_USER/.ssh/authorized_keys
chmod 600 /home/$SYSADMIN_USER/.ssh/authorized_keys
chown -R $SYSADMIN_USER:$SYSADMIN_USER /home/$SYSADMIN_USER/.ssh

# Secure SSH configuration
echo "Hardening SSH configuration..."
sed -i 's/^#Port 22/Port '"$SSH_PORT"'/g' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
systemctl restart sshd

# Set up firewall
echo "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow from $ALLOWED_IP to any port $SSH_PORT proto tcp
ufw enable

# Set password complexity rules
echo "Setting password complexity requirements..."
apt install libpam-pwquality -y
cat <<EOL > /etc/security/pwquality.conf
minlen = 12
minclass = 4
lcredit = -1
ucredit = -1
dcredit = -1
ocredit = -1
dictcheck = 0
EOL

# Set custom Bash prompt for sysadmin
echo "Customizing Bash prompt..."
echo 'export PS1="\[\033[01;32m\]\u@\h:\w\$ \[\033[00m\]"' >> /home/$SYSADMIN_USER/.bashrc

# Enable fail2ban
echo "Installing and enabling Fail2Ban..."
apt install fail2ban -y
systemctl enable fail2ban --now

# Set timezone to UTC
echo "Setting timezone to UTC..."
timedatectl set-timezone UTC

# Enable automatic security updates
echo "Configuring automatic security updates..."
apt install unattended-upgrades -y
systemctl enable unattended-upgrades

# Finish
echo "VPS setup complete. You may now log in as $SYSADMIN_USER."
