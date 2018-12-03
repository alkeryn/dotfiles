# Lines configured by zsh-newuser-install
source ~/.zplug/init.zsh

HISTFILE=~/.histfile
HISTSIZE=2000
SAVEHIST=2000
setopt extendedglob notify
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall

zstyle compinstall filename '/home/alkeryn/.zshrc'

# ZSH
autoload -Uz compinit promptinit
compinit
promptinit
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
#prompt elite

# Source

source ~/bin/shell/alias
source ~/bin/shell/env
source ~/bin/shell/utils
source ~/bin/shell/zsh
