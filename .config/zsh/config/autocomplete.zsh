# let autocomplete handle compinit
zstyle '*:compinit' arguments -D -i -u -C -w

# first insert the common substring
# all Tab widgets 
zstyle ':autocomplete:*complete*:*' insert-unambiguous yes 
# all history widgets 
zstyle ':autocomplete:*history*:*' insert-unambiguous yes 
# ^S 
zstyle ':autocomplete:menu-search:*' insert-unambiguous yes

# insert prefix instead of substring 
zstyle ':completion:*:*' matcher-list 'm:{[:lower:]-}={[:upper:]_}' '+r:|[.]=**'
builtin zstyle ':autocomplete:*:unambiguous' format \
    $'%{\e[0;2m%}%Bcommon substring:%b %0F%11K%d%f%k'

# make enter submitive command line straight from the CLI 
bindkey -M menuselect '\r' .accept-line

# add or don't add a space after a certain completions 
zstyle ':autocomplete:*' add-space \
    executables aliases functions builtins reserved-words commands

# start every command in history search mode

