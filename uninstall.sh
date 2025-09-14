#!/bin/bash
set -e
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "Stopping and disabling the service..."
systemctl stop theft-protect.service
systemctl disable theft-protect.service

echo "Removing installed files..."
rm -f /usr/local/bin/theft-protect-daemon.py
rm -f /usr/local/bin/lock-screen.sh
rm -f /etc/systemd/system/theft-protect.service

# Ask before removing configuration to preserve user settings
read -p "Do you want to remove the configuration directory /etc/theft-protect? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    rm -rf /etc/theft-protect
    echo "Configuration directory removed."
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Uninstallation complete."