ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(bracketed-paste up-line-or-search down-line-or-search expand-or-complete accept-line push-line-or-edit)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#bd93f9,bg=#50fa7b,bold,underline"
ZSH_AUTOSUGGEST_USE_ASYNC=true


zstyle ':autocomplete:*' widget-style menu-select
zstyle ':autocomplete:*' list-lines 7
bindkey '^I' autosuggest-accept
