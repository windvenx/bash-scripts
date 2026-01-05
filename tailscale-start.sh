#!/bin/bash
AUTHKEY="tskey-auth----------------------------------------"

if ! systemctl is-active --quiet tailscaled; then
  sudo systemctl start tailscaled
fi

sudo tailscale up --authkey="$AUTHKEY" --reset

echo "✅ Подключены к Tailscale сети"
