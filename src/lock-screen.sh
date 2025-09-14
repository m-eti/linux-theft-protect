#!/bin/bash

# Find the active graphical session ID on the primary seat (seat0)
SESSION_ID=$(loginctl list-sessions --no-legend | grep 'seat0' | awk '{print $1}')

if [ -n "$SESSION_ID" ]; then
    # Use loginctl to lock the specific session. This command works across
    # different desktop environments (GNOME, KDE, etc.).
    logger "Theft-Protect: Found active session $SESSION_ID. Issuing lock command."
    loginctl lock-session "$SESSION_ID"
else
    logger "Theft-Protect: Could not find an active graphical session to lock."
    exit 1
fi

exit 0