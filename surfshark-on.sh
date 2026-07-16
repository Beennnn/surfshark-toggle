#!/usr/bin/env bash
# surfshark-on.sh — re-enable the VPN network service and bring the tunnel up.
# Undoes surfshark-off.sh. On-demand takes over again once the service is on.
set -uo pipefail
cd "$(dirname "$0")" && source ./lib.sh

# Re-enable the service (admin-only → sudo).
sudo /usr/sbin/networksetup -setnetworkserviceenabled "$SERVICE_NAME" on
sleep 1

# Kick the tunnel so we don't wait for the next on-demand trigger.
id="$(vpn_id)"
[ -n "$id" ] && /usr/sbin/scutil --nc start "$id" 2>/dev/null || true

echo "🔓 VPN ON — \"$SERVICE_NAME\" re-enabled and connecting."
