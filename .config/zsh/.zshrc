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

# Typwritten: https://typewritten.dev/#/installation; Dracula compliment, purple based
ZSH_THEME="typewritten"

export TYPEWRITTEN_SYMBOL="λ "
export DRACULA_TYPEWRITTEN_COLOR_MAPPINGS="primary:#d5ccff;secondary:#9580ff;info_neutral_1:#d0ffcc;info_neutral_2:#ffffcc;info_special:#ff9580;info_negative:#ff5555;notice:#ffff80;accent:#d5ccff"
export TYPEWRITTEN_COLOR_MAPPINGS="${DRACULA_TYPEWRITTEN_COLOR_MAPPINGS}"
export TYPEWRITTEN_PROMPT_LAYOUT="half_pure"

# dracula tty theme
source $HOME/.local/bin/dracula-tty.sh

# auto-ls
function cd(){
        builtin cd "$@" && command eza -lhA --no-time --group-directories-first --icons=always --color=always
}
alias ls="eza -lhA --no-time --group-directories-first --icons=always --color=always"

# theme
source $ZDOTDIR/themea/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh