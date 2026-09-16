#!/data/data/com.termux/files/usr/bin/bash
# Cron watchdog. Runs every minute, keeps sshd + keepalive + VNC alive.
#
# Install:
#   chmod +x ~/.termux/watchdog.sh
#   (crontab -l 2>/dev/null | grep -v watchdog.sh; echo "* * * * * ~/.termux/watchdog.sh") | crontab -
#
# This is the most reliable self-healing layer in practice: runsvdir dies with
# the Termux main process, but crond is an independent daemon.
#
# Log: ~/.termux/watchdog.log

LOG="$HOME/.termux/watchdog.log"

# --- sshd ---
if ! pgrep -f "sshd -D" >/dev/null 2>&1; then
    sshd 2>/dev/null
    echo "$(date '+%F %T') sshd restarted" >> "$LOG"
fi

# --- audio keepalive ---
if [ -f "$HOME/.termux/quiet_1min.amr" ]; then
    if ! pgrep -f "termux-media-player play" >/dev/null 2>&1; then
        setsid nohup sh -c 'while true; do
            termux-media-player play "$HOME/.termux/quiet_1min.amr" >/dev/null 2>&1
            sleep 55
        done' >/dev/null 2>&1 < /dev/null &
        echo "$(date '+%F %T') keepalive restarted" >> "$LOG"
    fi
fi

# --- VNC (only if the autostart marker exists, so it can be disabled to save power) ---
if [ -f "$HOME/.vnc/autostart" ]; then
    if ! pgrep -f "Xvnc :1" >/dev/null 2>&1; then
        setsid nohup "$HOME/start-vnc.sh" >/dev/null 2>&1 < /dev/null &
        echo "$(date '+%F %T') vnc restarted" >> "$LOG"
    fi
fi
