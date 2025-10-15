#!/bin/bash

set -e

echo "Starting installation of Linux Theft Protection..."

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

if [ -n "$SUDO_USER" ]; then
    LOGGED_IN_USER="$SUDO_USER"
else
    LOGGED_IN_USER=$(logname)
fi

USER_HOME=$(getent passwd "$LOGGED_IN_USER" | cut -d: -f6)

if [ -z "$USER_HOME" ]; then
    echo "Could not find home directory for user $LOGGED_IN_USER. Exiting."
    exit 1
fi

INSTALL_PATH="/usr/local/bin"
CONFIG_DIR="/etc/theft-protect"
USER_SERVICE_PATH="$USER_HOME/.config/systemd/user"

echo "Creating system-wide directories..."
mkdir -p "$CONFIG_DIR"

echo "Installing main scripts to $INSTALL_PATH..."
cp src/theft-protect-daemon.py "$INSTALL_PATH/"
cp src/lock-screen.sh "$INSTALL_PATH/"

echo "Setting executable permissions..."
chmod +x "$INSTALL_PATH/theft-protect-daemon.py"
chmod +x "$INSTALL_PATH/lock-screen.sh"

echo "Installing systemd user service for user $LOGGED_IN_USER..."
sudo -u "$LOGGED_IN_USER" mkdir -p "$USER_SERVICE_PATH"
cp system/theft-protect.service "$USER_SERVICE_PATH/"

echo "Configuring service file for user context..."
sed -i '/^User=/d' "$USER_SERVICE_PATH/theft-protect.service"

if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    echo "Installing default configuration file..."
    cp config.ini.example "$CONFIG_DIR/config.ini"
else
    echo "Existing configuration file found. Skipping installation of default."
fi

echo "Enabling and reloading the user service..."
export XDG_RUNTIME_DIR="/run/user/$(id -u $LOGGED_IN_USER)"
sudo -E -u "$LOGGED_IN_USER" systemctl --user daemon-reload
sudo -E -u "$LOGGED_IN_USER" systemctl --user enable theft-protect.service

echo "Installation complete!"
echo "The service will now start automatically whenever '$LOGGED_IN_USER' logs in."
echo "To manually start it, run (without sudo): systemctl --user start theft-protect.service"
echo "To check its status, run (without sudo): systemctl --user status theft-protect.service"
echo "Please review the settings in $CONFIG_DIR/config.ini to adjust sensitivity."