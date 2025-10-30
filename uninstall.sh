#!/bin/bash

set -e

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

USER_SERVICE_FILE="$USER_HOME/.config/systemd/user/theft-protect.service"

echo "Stopping and disabling the user service for $LOGGED_IN_USER..."

# Check if the user's systemd instance is running. If not, we can't run systemctl --user.
if ! pgrep -u "$LOGGED_IN_USER" systemd > /dev/null; then
    echo "Warning: User '$LOGGED_IN_USER' does not have a running systemd user instance."
    echo "Could not stop or disable the service automatically."
    echo "The service file will be removed, which should prevent it from starting on next login."
else
    # Use runuser to correctly execute commands within the user's session context
    # Stop and disable the service, ignoring errors if it's already stopped/disabled
    runuser -l "$LOGGED_IN_USER" -c "systemctl --user stop theft-protect.service" || true
    runuser -l "$LOGGED_IN_USER" -c "systemctl --user disable theft-protect.service" || true
fi

echo "Removing installed files..."
rm -f /usr/local/bin/theft-protect-daemon.py
rm -f /usr/local/bin/lock-screen.sh

if [ -f "$USER_SERVICE_FILE" ]; then
    rm -f "$USER_SERVICE_FILE"
    echo "Removed systemd user service file."
fi

read -p "Do you want to remove the configuration directory /etc/theft-protect? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    rm -rf /etc/theft-protect
    echo "Configuration directory removed."
fi

if pgrep -u "$LOGGED_IN_USER" systemd > /dev/null; then
    echo "Reloading systemd user daemon..."
    runuser -l "$LOGGED_IN_USER" -c "systemctl --user daemon-reload"
fi

echo "Uninstallation complete."