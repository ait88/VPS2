# ~/.bash_aliases

# Safe upgrade
alias aptup='sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove --purge -y'

# Quick update only (no upgrade)
alias aptcheck='sudo apt update && apt list --upgradable'

# Reboot shortcut
alias rebootnow='sudo systemctl reboot'

# Ceph health check
alias cephok='ceph -s | grep -q HEALTH_OK && echo "🟢 Ceph is healthy" || ceph -s'
