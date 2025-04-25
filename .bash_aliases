# ~/.bash_aliases

# Safe upgrade (auto sudo if needed)
aptup() {
    if [ "$EUID" -ne 0 ]; then
        sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove --purge -y
    else
        apt update && apt full-upgrade -y && apt autoremove --purge -y
    fi
}

# Just list upgradable packages
aptcheck() {
    if [ "$EUID" -ne 0 ]; then
        sudo apt update && apt list --upgradable
    else
        apt update && apt list --upgradable
    fi
}

# Reboot wrapper
rebootnow() {
    if [ "$EUID" -ne 0 ]; then
        sudo systemctl reboot
    else
        systemctl reboot
    fi
}
