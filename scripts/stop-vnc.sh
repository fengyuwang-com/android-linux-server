#!/data/data/com.termux/files/usr/bin/bash
# Stop the VNC desktop and release the wake lock.

vncserver -kill :1 2>/dev/null
pkill -f Xtigervnc 2>/dev/null
termux-wake-unlock 2>/dev/null

echo "✅ VNC stopped"
