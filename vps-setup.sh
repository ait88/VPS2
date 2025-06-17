#!/bin/bash

# Prompt for user input
read -p "Enter your preferred username: " SYSADMIN_USER
ALLOWED_IPS=()
while true; do
    read -p "Enter an allowed IP for SSH access (or leave blank to finish): " ip
    [[ -z "$ip" ]] && break
    ALLOWED_IPS+=("$ip")
done

read -p "Enter GitHub username for SSH key retrieval: " GITHUB_USERNAME

# Prompt for a secure password
echo "Enter a password for $SYSADMIN_USER (must meet complexity requirements):"
while true; do
    read -s -p "Password: " SYSADMIN_PASS
    echo
    read -s -p "Confirm Password: " SYSADMIN_PASS_CONFIRM
    echo
    if [[ "$SYSADMIN_PASS" != "$SYSADMIN_PASS_CONFIRM" ]]; then
        echo "Passwords do not match. Try again."
        continue
    fi
    if ! [[ "$SYSADMIN_PASS" =~ [a-z] && "$SYSADMIN_PASS" =~ [A-Z] && "$SYSADMIN_PASS" =~ [0-9] && "$SYSADMIN_PASS" =~ [^a-zA-Z0-9] && ${#SYSADMIN_PASS} -ge 10 ]]; then
        echo "Password does not meet complexity requirements. It must have at least 10 characters, including uppercase, lowercase, a number, and a special character."
        continue
    fi
    break
done

SSH_PORT=22

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Update system
echo "Updating system..."
apt update && apt upgrade -y

# Install essential tools
echo "Installing essential utilities (curl, ufw, wget, nano, net-tools, rsync)..."
apt install -y curl ufw wget nano net-tools rsync

# Set password complexity rules
echo "Setting password complexity requirements..."
apt install libpam-pwquality -y
cat <<EOL > /etc/security/pwquality.conf
minlen = 10
minclass = 4
lcredit = -1
ucredit = -1
dcredit = -1
ocredit = -1
dictcheck = 0
EOL

# Create sysadmin user if it doesn't exist
if ! id "$SYSADMIN_USER" &>/dev/null; then
    echo "Creating user $SYSADMIN_USER..."
    adduser --gecos "" --disabled-password $SYSADMIN_USER
    echo "$SYSADMIN_USER:$SYSADMIN_PASS" | chpasswd
    usermod -aG sudo $SYSADMIN_USER
fi

# Install btop
apt update && apt install -y btop

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
echo "Configuring  firewall..."
 --force reset
 default deny incoming
 default allow outgoing
for ip in "${ALLOWED_IPS[@]}"; do
     allow from $ip to any port $SSH_PORT proto tcp
done
 enable &&  reload

# Fetch and apply custom Bash profile from GitHub
echo "Fetching custom Bash profile..."
curl -sL https://raw.githubusercontent.com/ait88/VPS/main/.bashrc -o /home/$SYSADMIN_USER/.bashrc
chown $SYSADMIN_USER:$SYSADMIN_USER /home/$SYSADMIN_USER/.bashrc
chmod 644 /home/$SYSADMIN_USER/.bashrc

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
