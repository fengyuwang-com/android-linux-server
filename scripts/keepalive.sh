#!/data/data/com.termux/files/usr/bin/bash
# Audio-focus keepalive: makes Android believe Termux is playing media,
# which exempts it from the screen-off freeze that otherwise kills sshd.
#
# Why this works: Android grants an exemption to processes holding audio focus
# ("user-perceivable task"), so they are not moved into the cached/frozen
# process group. termux-wake-lock alone does NOT prevent this freeze - it only
# prevents CPU sleep.
#
# Requires: Termux:API APK installed, ~/.termux/quiet_1min.amr present.
# Cost: continuous battery drain.

termux-wake-lock 2>/dev/null

[ -f "$HOME/.termux/quiet_1min.amr" ] || exit 0

# Idempotent: only start the loop if it is not already running.
# pgrep -f is required; the process name carries arguments.
if ! pgrep -f "termux-media-player play" >/dev/null 2>&1; then
    # setsid  - detach from the controlling terminal so it survives SSH logout
    # nohup   - ignore SIGHUP
    # </dev/null - prevent the loop from blocking on stdin
    setsid nohup sh -c 'while true; do
        termux-media-player play "$HOME/.termux/quiet_1min.amr" >/dev/null 2>&1
        sleep 55
    done' >/dev/null 2>&1 < /dev/null &
fi
