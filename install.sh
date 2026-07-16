#!/usr/bin/env bash
# install.sh — install a tightly-scoped NOPASSWD sudoers rule so the toggle
# scripts (and a Stream Deck button / Shortcut) can enable/disable the VPN
# network service without a password prompt.
#
# Why a sudoers rule at all: enabling/disabling a macOS network service is an
# admin-only operation (`networksetup -setnetworkserviceenabled`). Without the
# rule, every off/on would pop a password dialog — unusable from a hardware
# button.
#
# Why the rule is scoped to the SUBCOMMAND, not the exact service string:
# the service name contains a space and a ® ("Surfshark. WireGuard®"), which
# sudoers argument matching cannot express cleanly. So we grant NOPASSWD for
# `networksetup -setnetworkserviceenabled` only. That subcommand can only
# enable/disable services — it cannot create/delete services, change routes,
# DNS, or proxies. Bounded and reversible.
set -euo pipefail

USER_NAME="$(id -un)"
RULE_FILE="/etc/sudoers.d/surfshark-toggle"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

cat > "$TMP" <<EOF
# Installed by surfshark-toggle/install.sh
# Allow $USER_NAME to enable/disable any network service without a password.
# Scoped to the single subcommand -setnetworkserviceenabled (enable/disable only).
$USER_NAME ALL=(root) NOPASSWD: /usr/sbin/networksetup -setnetworkserviceenabled *
EOF

# Validate BEFORE touching /etc/sudoers.d — a malformed sudoers file can lock
# you out of sudo entirely. visudo -cf refuses to install anything invalid.
if ! sudo visudo -cf "$TMP" >/dev/null; then
  echo "❌ generated sudoers rule failed validation — aborting, nothing installed."
  exit 1
fi

sudo install -m 0440 -o root -g wheel "$TMP" "$RULE_FILE"
echo "✅ installed $RULE_FILE"
echo "   test with:  ./surfshark-off.sh   (should NOT prompt for a password)"
