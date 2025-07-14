export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.config/hypr/scripts:$HOME:$PATH"

# keyring
if [ -n "$DESKTOP_SESSION" ]; then
  eval $(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh -d)
  export SSH_AUTH_SOK
fi
