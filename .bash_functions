# ~/.bash_functions

aptup() {
    if [ "$EUID" -ne 0 ]; then
        sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove --purge -y
    else
        apt update && apt full-upgrade -y && apt autoremove --purge -y
    fi
}

aptcheck() {
    if [ "$EUID" -ne 0 ]; then
        sudo apt update && apt list --upgradable
    else
        apt update && apt list --upgradable
    fi
}

rebootnow() {
    if [ "$EUID" -ne 0 ]; then
        sudo systemctl reboot
    else
        systemctl reboot
    fi
}
