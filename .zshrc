# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=2000
SAVEHIST=2000
setopt extendedglob notify
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall

zstyle compinstall filename '/home/alkeryn/.zshrc'

# Alias
alias rm="\rm"
alias myip="curl -4 ifconfig.co; curl -6 ifconfig.co"
alias cpd="cp -axrfT"
alias cpa="cp -axvuf"
alias ls='ls --color'
alias up='sudo pacman -Syu --noconfirm'
alias up2='aurman -Syu --noconfirm --noedit --pgp_fetch'
alias xev='~/bin/xev'
alias vim='nvim'
alias visudo='sudo EDITOR=nvim visudo'
alias vipw='sudo EDITOR=nvim vipw'
alias vigr='sudo EDITOR=nvim vigr'
alias sudo='sudo -E'
alias viw='nvim -m'
alias view='nvim -m'
alias rmlog='sudo journalctl --vacuum-time=2weeks'
alias clearlog='sudo rm -rf /var/log/journal/*'
alias cls='clear'
alias sspd='systemctl suspend && lock'
alias caup='update-desktop-database ~/.local/share/applications && update-mime-database ~/.local/share/mime/ && echo Done'
alias webcam='mpv tv:// --tv-driver=v4l2 --tv-device=/dev/video0'
alias winetricks='sh winetricks'
alias speedtest='speedtest --bytes'
alias gpg='gpg --keyserver pgp.mit.edu'
alias rangimg='while true; do pkill w3mimgdisplay; sleep 5;done'
alias screen="screen -q"
alias diff="diff --color=always"
alias restartpulse='pulseaudio -k && sleep 2 && pulseaudio --start; optirun true &'
alias gpuswitch='sudo gpuswitch'
alias kbedit='vim ~/bin/Software/qmk_firmware/keyboards/planck/keymaps/alkeryn/'
alias kbmake='pushd ~/bin/Software/qmk_firmware ; sudo make planck:alkeryn:dfu ; popd'
alias dl="youtube-dl"
alias weather="curl wttr.in/~Mulhouse"
alias mct="\sudo machinectl"
alias shell="\sudo machinectl shell"
alias nspawn="\sudo systemd-nspawn -E TERM=xterm -E DISPLAY=$DISPLAY"
alias kali="\sudo machinectl shell kali"
alias zz="7z"
alias rax="rax2"
alias op="xdg-open"
# alias msfconsole="msfconsole --quiet -x \"db_connect ${USER}@msf\""
alias :q="exit"

# ZSH
autoload -Uz compinit promptinit
compinit
promptinit
#prompt elite
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
#source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh


# Definition

export VISUAL=nvim
export EDITOR=nvim
export PATH=$PATH:~/bin:~/bin/launch
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export ZPOOL_VDEV_NAME_PATH=YES
stock=/run/media/alkeryn/Stock
stock2=/run/media/alkeryn/Stock2

# key bindings
export KEYTIMEOUT=1
bindkey -e
bindkey    "^[[3~"          delete-char
bindkey    "^[3;5~"         delete-char
#bindkey "e[1~" beginning-of-line
#bindkey "e[4~" end-of-line
#bindkey "e[5~" beginning-of-history
#bindkey "e[6~" end-of-history
#bindkey "e[3~" delete-char
#bindkey "e[2~" quoted-insert
#bindkey "e[5C" forward-word
#bindkey "eOc" emacs-forward-word
#bindkey "e[5D" backward-word
#bindkey "eOd" emacs-backward-word
#bindkey "ee[C" forward-word
#bindkey "ee[D" backward-word
bindkey "^H" backward-delete-word
# for rxvt
#bindkey "e[8~" end-of-line
#bindkey "e[7~" beginning-of-line
# for non RH/Debian xterm, can't hurt for RH/DEbian xterm
#bindkey "eOH" beginning-of-line
#bindkey "eOF" end-of-line
## for freebsd console
#bindkey "e[H" beginning-of-line
#bindkey "e[F" end-of-line
# completion in the middle of a line
#bindkey '^i' expand-or-complete-prefix
# End of lines added by compinstall

# Functions

md () { mkdir -p "$@" && cd "$1"; }
winvm () {
	~/bin/winvm $1 &
}
ddusb (){
        vara=$1
        varb=$2
        shift 2
sudo dd bs=4M if="$vara" of="$varb" status=progress oflag=sync $@
}

# FIX issue with echo -n & similar output not showing
 # Skip defining precmd if the PROMPT_SP option is available.
    if ! eval '[[ -o promptsp ]] 2>/dev/null'; then
      function precmd {
        # Output an inverse char and a bunch spaces.  We include
        # a CR at the end so that any user-input that gets echoed
        # between this output and the prompt doesn't cause a wrap.
        print -nP "%B%S%#%s%b${(l:$((COLUMNS-1)):::):-}\r"
      }
    fi
