#!/usr/bin/env bash
# surfshark-off.sh — actually turn the VPN OFF and keep it off.
#
# Why this is not just `scutil --nc stop`:
# Surfshark installs a VPN profile with On-Demand enabled and an
# unconditional `Action: Connect` rule. macOS's on-demand engine recomposes
# the tunnel the instant any traffic matches — so `scutil --nc stop` succeeds
# for a fraction of a second, then the tunnel comes right back.
# You cannot defeat on-demand from user space.
#
# The one reliable parade: DISABLE THE NETWORK SERVICE itself. On-demand
# cannot connect a service that is administratively disabled. Reversible with
# surfshark-on.sh. Requires one scoped NOPASSWD sudoers rule (see install.sh).
set -uo pipefail
cd "$(dirname "$0")" && source ./lib.sh

# Disable the service (admin-only → sudo). This is what makes it stick.
sudo /usr/sbin/networksetup -setnetworkserviceenabled "$SERVICE_NAME" off

# Tear down the tunnel that may still be up right now.
id="$(vpn_id)"
[ -n "$id" ] && /usr/sbin/scutil --nc stop "$id" 2>/dev/null || true

echo "🔒 VPN OFF — \"$SERVICE_NAME\" disabled; on-demand can no longer reconnect it."
