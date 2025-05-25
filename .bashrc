# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

CUSTOM_START='####CUSTOM CONFIG####'
CUSTOM_END='####END CUSTOM CONFIG####'

####CUSTOM CONFIG####
##anything between these lines will persist when .bashrc is auto-updated##
##============================##
# Locally persistent .bashrc lines
##============================##
####END CUSTOM CONFIG####

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    prompt_color='\[\033[;32m\]'
    info_color='\[\033[1;34m\]'
    prompt_symbol=📛
    if [ "$EUID" -eq 0 ]; then
        prompt_color='\[\033[;94m\]'
        info_color='\[\033[1;31m\]'
        prompt_symbol=💀
    fi
    PS1="${prompt_color}┌──${debian_chroot:+($debian_chroot)──}(${info_color}\u${prompt_symbol}\h${prompt_color})-[\[\033[0;1m\]\w${prompt_color}]\n${prompt_color}└─${info_color}\\$ \[\033[0m\] "
fi

unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls, less and man, and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip --color=auto'

    export LESS_TERMCAP_mb=$'\E[1;31m'
    export LESS_TERMCAP_md=$'\E[1;36m'
    export LESS_TERMCAP_me=$'\E[0m'
    export LESS_TERMCAP_so=$'\E[01;33m'
    export LESS_TERMCAP_se=$'\E[0m'
    export LESS_TERMCAP_us=$'\E[1;32m'
    export LESS_TERMCAP_ue=$'\E[0m'
fi

alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Alias definitions.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Enable programmable completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# ─── Show aliases/functions on login ─────────────────────────────
if [[ -n "$PS1" && -f ~/.bash_aliases ]]; then
    echo -e "\033[1;36m Available Aliases:\033[0m"
    grep '^alias ' ~/.bash_aliases | sed -E 's/^alias ([^=]+)=.*/\1/' | while read -r aliasname; do
        echo -e "  \033[0;32m${aliasname}\033[0m"
    done
fi

if [[ -n "$PS1" && -f ~/.bash_functions ]]; then
    echo -e "\033[1;36m Available Functions:\033[0m"
    grep -E '^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' ~/.bash_functions | sed -E 's/^([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\).*/\1/' | while read -r fname; do
        echo -e "  \033[0;32m${fname}\033[0m"
    done
fi

# Check if a reboot is required
if [ -f /var/run/reboot-required ]; then
  echo -e "\033[1;31m🔁 Reboot is required!\033[0m"
else
  echo -e "\033[1;32m✅ No reboot needed\033[0m"
fi

# Auto-update .bashrc, .bash_aliases, and .bash_functions from GitHub
GITHUB_BASE_URL="https://raw.githubusercontent.com/ait88/VPS/main"
LOCAL_BASHRC="$HOME/.bashrc"
LOCAL_BASH_ALIASES="$HOME/.bash_aliases"
LOCAL_BASH_FUNCTIONS="$HOME/.bash_functions"

update_file() {
    local url="$1"
    local dest="$2"
    local tmp="${dest}.tmp"
    local merged="${dest}.merged"

    if curl -fsSL "$url" -o "$tmp"; then
        # Only preserve the custom config for .bashrc
        if [ "$dest" = "$LOCAL_BASHRC" ] && \
           grep -q "$CUSTOM_START" "$dest" && grep -q "$CUSTOM_END" "$dest"; then
            # Extract custom config block from the existing file
            awk "/$CUSTOM_START/,/$CUSTOM_END/" "$dest" > /tmp/custom_config_block.txt
            # Remove custom config block from the new file (if present)
            awk "BEGIN{p=1} /$CUSTOM_START/{p=0} /$CUSTOM_END/{p=1; next} p" "$tmp" > "$tmp.nocustom"
            # Insert custom block after the first line (adapt NR==1 if needed)
            awk "NR==6{print; system(\"cat /tmp/custom_config_block.txt\"); next} 1" "$tmp.nocustom" > "$merged"
            # Compare merged result with local file
            if ! cmp -s "$dest" "$merged"; then
                echo "Replacing $dest with updated version"
                mv "$merged" "$dest"
                echo "Updated $(basename "$dest") from GitHub."
                [ "$dest" = "$LOCAL_BASHRC" ] && exec bash
            fi
            rm -f "$tmp" "$tmp.nocustom" /tmp/custom_config_block.txt "$merged"
        else
            # No custom block to preserve: regular compare
            if [ -s "$tmp" ] && ! cmp -s "$dest" "$tmp"; then
                echo "Replacing $dest with updated version"
                mv "$tmp" "$dest"
                echo "Updated $(basename "$dest") from GitHub."
                [ "$dest" = "$LOCAL_BASHRC" ] && exec bash
            else
                rm -f "$tmp"
            fi
        fi
    fi
}

if command -v curl >/dev/null 2>&1; then
    update_file "$GITHUB_BASE_URL/.bashrc" "$LOCAL_BASHRC"
    update_file "$GITHUB_BASE_URL/.bash_aliases" "$LOCAL_BASH_ALIASES"
    update_file "$GITHUB_BASE_URL/.bash_functions" "$LOCAL_BASH_FUNCTIONS"

    [ -f "$LOCAL_BASH_ALIASES" ] && source "$LOCAL_BASH_ALIASES"
    [ -f "$LOCAL_BASH_FUNCTIONS" ] && source "$LOCAL_BASH_FUNCTIONS"
fi
