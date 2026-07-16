#!/usr/bin/env bash
# uninstall.sh — remove the NOPASSWD sudoers rule installed by install.sh.
# Leaves the network service in whatever state it's currently in (run
# surfshark-on.sh first if you want the VPN back on before removing the rule).
set -euo pipefail

RULE_FILE="/etc/sudoers.d/surfshark-toggle"

if [ ! -f "$RULE_FILE" ]; then
  echo "nothing to do — $RULE_FILE not present."
  exit 0
fi

sudo rm -f "$RULE_FILE"
echo "🗑  removed $RULE_FILE — off/on will now prompt for a password again."
