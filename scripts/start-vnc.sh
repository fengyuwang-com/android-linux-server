#!/data/data/com.termux/files/usr/bin/bash
# Start the XFCE4 desktop over TigerVNC on display :1 (port 5901).
#
# -localhost no is required for remote access; the tigervnc.conf setting alone
# is not always honoured.

export DISPLAY=:1
termux-wake-lock

# Tear down any previous session
vncserver -kill :1 >/dev/null 2>&1
pkill -f Xtigervnc 2>/dev/null
sleep 1

# Start
vncserver :1 -geometry 1920x1080 -depth 24 -localhost no 2>&1 | tail -5
sleep 2

if pgrep -f "Xvnc :1" >/dev/null; then
    echo "✅ VNC started on port 5901"
    echo "   Connect: vncviewer <phone-ip>:5901"
else
    echo "❌ Failed to start. Log:"
    tail -20 "$HOME"/.vnc/*:1.log 2>/dev/null
    exit 1
fi
