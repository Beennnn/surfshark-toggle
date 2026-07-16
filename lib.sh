#!/usr/bin/env bash
# lib.sh — shared config + helpers for surfshark-toggle.
# Sourced by surfshark-on.sh / surfshark-off.sh / surfshark-status.sh.

# Name of the macOS network service to toggle, exactly as it appears in
# `scutil --nc list` / System Settings › Network. Override via env if yours
# differs (e.g. the OpenVPN service, or a non-Surfshark WireGuard VPN):
#   SURFSHARK_SERVICE="Surfshark. OpenVPN (TCP)" ./surfshark-off.sh
SERVICE_NAME="${SURFSHARK_SERVICE:-Surfshark. WireGuard®}"

# Resolve the scutil connection ID (a UUID) from the human service name.
# We DON'T hardcode the UUID: it is per-install and changes if the VPN
# config is re-added. Deriving it from the stable display name keeps the
# scripts portable across machines and re-installs.
vpn_id() {
  scutil --nc list 2>/dev/null \
    | grep -F "\"$SERVICE_NAME\"" \
    | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | head -1
}

# Is the tunnel currently up?
vpn_connected() {
  scutil --nc list 2>/dev/null | grep -F "\"$SERVICE_NAME\"" | grep -q "(Connected)"
}
