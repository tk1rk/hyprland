export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.config/hypr/scripts:$HOME:$PATH"

# keyring
if [ -n "$DESKTOP_SESSION" ]; then
  eval $(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh -d)
  export SSH_AUTH_SOCK
fi

# Dracula theme for GNU grep - https://draculatheme.com/grep
export GREP_COLORS="mt=1;38;2;255;85;85:fn=38;2;255;121;198:ln=38;2;80;250;123:bn=38;2;80;250;123:se=38;2;139;233;253"
# Dracula theme for BSD grep - https://draculatheme.com/grep
export GREP_COLOR="1;38;2;255;85;85"
