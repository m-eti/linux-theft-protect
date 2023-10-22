#!/bin/bash

SESSION_ID=$(loginctl list-sessions --no-legend | grep 'seat0' | awk '{print $1}')

if [ -n "$SESSION_ID" ]; then
    logger -t "theft-protect" "Found active session $SESSION_ID. Issuing lock command."
    loginctl lock-session "$SESSION_ID"
else
    logger -t "theft-protect" "Could not find an active graphical session to lock."
    exit 1
fi

exit 0
