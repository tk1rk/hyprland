# Enable Powerlevel10k
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# zsh exec
ZDOTDIR='$HOME/.config/zsh'
ZCACHE='$XDG_CACHE_HOME/zsh'
ZCONFIG='$ZDOTDIR/config'
export ZCACHE ZCONFIG ZPLUGI

# zsh source
for i in "$file" do;
	source "$ZCONFIG/autocomplete.zsh"
	source "$ZCONFIG/autosuggestions.zsh"
	source "$ZCONFIG/bindkeys.zsh"
	source "$ZCONFIG/completion.zsh"
	source "$ZCONFIG/functions.zsh"
end

# fpath
fpath=(~/.cache/zsh/completions $fpath)
autoload _autols

# plugin manager


# dracula tty theme
source $HOME/.local/bin/dracula-tty.sh

# auto-ls
function cd(){
        builtin cd "$@" && command eza -lhA --no-time --group-directories-first --icons=always --color=always
}
alias ls="eza -lhA --no-time --group-directories-first --icons=always --color=always"

# theme
source $ZDOTDIR/themes/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh