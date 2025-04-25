# ~/.bash_aliases

# System cleanup & package management:
alias cls='clear && source ~/.bashrc'
alias update='apt update && apt list --upgradable'
alias upgrade='apt full-upgrade -y'
alias cleanup='apt autoremove --purge -y && apt clean'

# System info:
alias mem='free -h'
alias cpu='lscpu | grep "Model name\|CPU(s)"'
alias disk='lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT'
alias dfh='df -h'
alias du1='du -sh * 2>/dev/null | sort -h'

# Networking:
alias ports='ss -tuln'
alias ipinfo='ip -brief address'
alias pingg='ping 8.8.8.8'
