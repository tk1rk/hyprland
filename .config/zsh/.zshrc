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

if [ "$TERM" = "linux" ]; then
	printf %b '\e[40m' '\e[8]' # set default background to color 0 'dracula-bg'
	printf %b '\e[37m' '\e[8]' # set default foreground to color 7 'dracula-fg'
	printf %b '\e]P0282a36'    # redefine 'black'          as 'dracula-bg'
	printf %b '\e]P86272a4'    # redefine 'bright-black'   as 'dracula-comment'
	printf %b '\e]P1ff5555'    # redefine 'red'            as 'dracula-red'
	printf %b '\e]P9ff7777'    # redefine 'bright-red'     as '#ff7777'
	printf %b '\e]P250fa7b'    # redefine 'green'          as 'dracula-green'
	printf %b '\e]PA70fa9b'    # redefine 'bright-green'   as '#70fa9b'
	printf %b '\e]P3f1fa8c'    # redefine 'brown'          as 'dracula-yellow'
	printf %b '\e]PBffb86c'    # redefine 'bright-brown'   as 'dracula-orange'
	printf %b '\e]P4bd93f9'    # redefine 'blue'           as 'dracula-purple'
	printf %b '\e]PCcfa9ff'    # redefine 'bright-blue'    as '#cfa9ff'
	printf %b '\e]P5ff79c6'    # redefine 'magenta'        as 'dracula-pink'
	printf %b '\e]PDff88e8'    # redefine 'bright-magenta' as '#ff88e8'
	printf %b '\e]P68be9fd'    # redefine 'cyan'           as 'dracula-cyan'
	printf %b '\e]PE97e2ff'    # redefine 'bright-cyan'    as '#97e2ff'
	printf %b '\e]P7f8f8f2'    # redefine 'white'          as 'dracula-fg'
	printf %b '\e]PFffffff'    # redefine 'bright-white'   as '#ffffff'
	clear
fi

# auto-ls
function cd(){
        builtin cd "$@" && command eza -lhA --no-time --group-directories-first --icons=always --color=always
}
alias ls="eza -lhA --no-time --group-directories-first --icons=always --color=always"

# theme
source $ZDOTDIR/themea/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh