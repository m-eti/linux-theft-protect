#!/bin/bash

set -euo pipefail

SCRIPT_NAME="theft-protect"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/theft-protect"
BIN_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"

# --- Logging ---
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# --- Pre-flight Checks ---
if [ "$EUID" -eq 0 ]; then
    error "Do not run this script as root. It uninstalls for the current user only."
    exit 1
fi

info "Uninstalling $SCRIPT_NAME for user $(whoami)..."

# --- Stop and Disable Service ---
if systemctl --user is-active theft-protect.service &>/dev/null; then
    info "Stopping theft-protect service..."
    systemctl --user stop theft-protect.service
fi

if systemctl --user is-enabled theft-protect.service &>/dev/null; then
    info "Disabling theft-protect service..."
    systemctl --user disable theft-protect.service
fi

# --- Remove Installed Files ---
info "Removing installed files..."
rm -f "$BIN_DIR/theft-protect-daemon.sh"
rm -f "$BIN_DIR/lock-screen.sh"
rm -f "$SERVICE_DIR/theft-protect.service"

# --- Reload Systemd ---
info "Reloading systemd user daemon..."
systemctl --user daemon-reload 2>/dev/null || true

# --- Optionally Remove Config ---
echo ""
if [ -d "$CONFIG_DIR" ]; then
    read -r -p "Remove configuration directory $CONFIG_DIR? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm -rf "$CONFIG_DIR"
        info "Configuration directory removed."
    else
        info "Keeping configuration directory."
    fi
fi

# --- Done ---
echo ""
info "Uninstallation complete."
