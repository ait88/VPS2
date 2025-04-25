# ~/.bash_aliases

# Safe upgrade
alias aptup='apt update && apt full-upgrade -y && apt autoremove --purge -y'

# Quick update only (no upgrade)
alias aptcheck='apt update && apt list --upgradable'

# Reboot shortcut
alias rebootnow='systemctl reboot'

# Ceph health check
alias cephok='ceph -s | grep -q HEALTH_OK && echo "🟢 Ceph is healthy" || ceph -s'
