# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# fpath
fpath=(~/.cache/zsh/completions $fpath)
autoload _autols

ZDOTDIR='$HOME/.config/zsh'
ZCACHE='$XDG_CACHE_HOME/zsh'
ZCONFIG='$ZDOTDIR/config'
ZPLUGIN='$ZDOTDIR/plugins'
export ZCACHE ZCONFIG ZPLUGIN

#source $ZCONFIG/aliaseses.zsh
#source $ZCONFIG/autosuggestions.zsh
#source $ZCONFIG/bindkeys.zsh
#source $ZCONFIG/completions.zsh
#source $ZCONFIG/functions.zsh

# plugin manager
source ~/.zpm.zsh

# auto-ls
function cd(){
        builtin cd "$@" && command eza -lhA --no-time --group-directories-first --icons=always --color=always
}
alias ls="eza -lhA --no-time --group-directories-first --icons=always --color=always"

# theme
source $ZDOTDIR/themea/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh