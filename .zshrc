source ~/.zsh/antigen.zsh
source ~/bin/wpc

setopt extendedglob notify

# ZSH

eval $(dircolors -b)
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} #completion colors
zstyle ':completion:*' rehash true #reload path when new software installed

# Zplug


antigen use prezto
antigen bundle sorin-ionescu/prezto modules/environement
antigen bundle sorin-ionescu/prezto modules/terminal
antigen bundle sorin-ionescu/prezto modules/editor
antigen bundle sorin-ionescu/prezto modules/history
antigen bundle sorin-ionescu/prezto modules/directory
antigen bundle sorin-ionescu/prezto modules/spectrum
antigen bundle sorin-ionescu/prezto modules/utility
antigen bundle sorin-ionescu/prezto modules/completion
# antigen bundle sorin-ionescu/prezto modules/prompt

antigen bundle mafredri/zsh-async
antigen bundle sindresorhus/pure
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle spwhitt/nix-zsh-completions.git

antigen apply

# Source

source ~/bin/shell/alias
source ~/bin/shell/env
source ~/bin/shell/utils
source ~/bin/shell/zsh

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff"

HISTFILE=~/.zhistory
HISTSIZE=999999999
SAVEHIST=$HISTSIZE
