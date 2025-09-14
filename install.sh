#!/bin/bash

# Abort on any error
set -e

echo "Starting installation of Linux Theft Protection..."

# --- Check for root privileges ---
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# --- Define paths ---
INSTALL_PATH="/usr/local/bin"
CONFIG_DIR="/etc/theft-protect"
SERVICE_PATH="/etc/systemd/system"
LOGGED_IN_USER=$(logname)

# --- Create directories ---
echo "Creating configuration directory at $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR"

# --- Copy files ---
echo "Installing main scripts to $INSTALL_PATH..."
cp src/theft-protect-daemon.py "$INSTALL_PATH/"
cp src/lock-screen.sh "$INSTALL_PATH/"

echo "Installing systemd service file..."
cp system/theft-protect.service "$SERVICE_PATH/"

# --- Set permissions ---
echo "Setting executable permissions..."
chmod +x "$INSTALL_PATH/theft-protect-daemon.py"
chmod +x "$INSTALL_PATH/lock-screen.sh"

# --- Configure service for the correct user ---
echo "Configuring service to run as user: $LOGGED_IN_USER..."
# This replaces the placeholder 'your_username' with the actual user running the script
sed -i "s/User=your_username/User=$LOGGED_IN_USER/" "$SERVICE_PATH/theft-protect.service"

# --- Install configuration file ---
if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    echo "Installing default configuration file..."
    cp config.ini.example "$CONFIG_DIR/config.ini"
else
    echo "Existing configuration file found. Skipping installation of default."
fi

# --- Systemd setup ---
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling the theft-protect service to start on login..."
systemctl enable theft-protect.service

echo "Installation complete!"
echo "You can now start the service with: sudo systemctl start theft-protect.service"
echo "To check its status, use: systemctl status theft-protect.service"
echo "Please review the settings in $CONFIG_DIR/config.ini to adjust sensitivity."