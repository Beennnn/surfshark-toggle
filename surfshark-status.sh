#!/usr/bin/env bash
# surfshark-status.sh — is the VPN currently up, and is its service enabled?
set -uo pipefail
cd "$(dirname "$0")" && source ./lib.sh

echo "service : $SERVICE_NAME"

id="$(vpn_id)"
if [ -z "$id" ]; then
  echo "state   : ⚠️  service not found in \`scutil --nc list\`"
  echo "          (check the name — run: scutil --nc list)"
  exit 1
fi

if vpn_connected; then
  echo "tunnel  : 🔒 CONNECTED"
else
  echo "tunnel  : 🔓 disconnected"
fi

# Whether the network service itself is enabled (the thing off/on flips).
if /usr/sbin/networksetup -getnetworkserviceenabled "$SERVICE_NAME" 2>/dev/null | grep -q "^Enabled"; then
  echo "service : enabled  → on-demand CAN reconnect (run surfshark-off.sh to block it)"
else
  echo "service : disabled → on-demand CANNOT reconnect ✓"
fi
