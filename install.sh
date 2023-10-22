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
    error "Do not run this script as root. It installs for the current user only."
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

info "Installing $SCRIPT_NAME for user $(whoami)..."

# --- Create Directories ---
info "Creating directories..."
mkdir -p "$BIN_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$SERVICE_DIR"

# --- Install Scripts ---
info "Installing daemon and lock-screen script to $BIN_DIR..."
install -m 755 "$REPO_DIR/src/theft-protect-daemon.sh" "$BIN_DIR/theft-protect-daemon.sh"
install -m 755 "$REPO_DIR/src/lock-screen.sh"          "$BIN_DIR/lock-screen.sh"

# --- Install Configuration ---
if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    info "Installing default configuration to $CONFIG_DIR/config.ini..."
    install -m 644 "$REPO_DIR/config.ini.example" "$CONFIG_DIR/config.ini"
else
    info "Existing configuration found. Skipping."
fi

# --- Install Systemd User Service ---
info "Installing systemd user service..."
install -m 644 "$REPO_DIR/system/theft-protect.service" "$SERVICE_DIR/theft-protect.service"

# --- Enable Service ---
info "Reloading systemd user daemon..."
systemctl --user daemon-reload

info "Enabling theft-protect service..."
systemctl --user enable theft-protect.service

# --- Done ---
echo ""
info "Installation complete!"
echo ""
echo "  Config:   $CONFIG_DIR/config.ini"
echo "  Service:  $SERVICE_DIR/theft-protect.service"
echo ""
echo "  The service will start automatically on your next login."
echo "  To start it now:  systemctl --user start theft-protect"
echo "  To check status:  systemctl --user status theft-protect"
echo "  To view logs:     journalctl --user -u theft-protect -f"
echo ""
echo "  Edit $CONFIG_DIR/config.ini to adjust sensitivity."
