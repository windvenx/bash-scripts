#!/bin/bash
AUTHKEY="tskey-auth-kBvt9iWLsm11CNTRL-CbGRG4mJhGDsdbroAzdfGDmX1yGETEjW"

if ! systemctl is-active --quiet tailscaled; then
  sudo systemctl start tailscaled
fi

sudo tailscale up --authkey="$AUTHKEY" --reset

echo "✅ Подключены к Tailscale сети"
