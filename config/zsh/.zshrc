alias nixdev='nix develop --command zsh'
alias nixsh='nix-shell --run zsh'

bindkey '^R' history-incremental-search-backward

eval "$(starship init zsh)"
