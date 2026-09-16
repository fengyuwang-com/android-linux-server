#!/usr/bin/env bash
# Rescue a Termux sshd via ADB when SSH is unreachable.
#
# Run this from the PC when `ssh <phone>` gives "Connection refused" but the
# phone answers ping. That combination means the phone is up and the network is
# fine, but sshd is not listening inside Termux.
#
# Why force-stop + relaunch works: it creates a fresh login session, which runs
# ~/.bashrc, which starts sshd. This is the ONLY reliable ADB-to-Termux path -
# Termux's service is deliberately not exported, so you cannot inject commands.
#
# Usage:
#   ./rescue-via-adb.sh <phone-tailscale-ip> [ssh-port]
#
# Requires: adb on PATH (or ADB env var pointing at adb.exe)

set -u

PHONE_IP="${1:-<PHONE_IP>}"
SSH_PORT="${2:-8022}"
ADB="${ADB:-adb}"

echo "=== 1/4 Checking phone reachability ==="
if ! ping -c 2 "$PHONE_IP" >/dev/null 2>&1; then
    echo "❌ Phone does not answer ping at $PHONE_IP"
    echo "   Check: is the phone on? Is Tailscale running on it?"
    exit 1
fi
echo "✅ Phone answers ping"

echo
echo "=== 2/4 Checking ADB connection ==="
if ! "$ADB" devices | grep -q "device$"; then
    echo "❌ No ADB device. Connect the USB cable and set USB mode to MTP."
    "$ADB" devices
    exit 1
fi
"$ADB" devices | grep "device$"

echo
echo "=== 3/4 Restarting Termux ==="
"$ADB" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
"$ADB" shell am force-stop com.termux
sleep 3
"$ADB" shell am start -n com.termux/.app.TermuxActivity
echo "   Waiting for .bashrc to start sshd..."

echo
echo "=== 4/4 Verifying SSH ==="
for i in $(seq 1 10); do
    sleep 3
    if (echo > "/dev/tcp/$PHONE_IP/$SSH_PORT") 2>/dev/null; then
        echo "✅ SSH is back up (after $((i * 3))s)"
        exit 0
    fi
    printf "."
done

echo
echo "❌ Still down after 30s."
echo "   Next steps:"
echo "   1. Check the Termux window on the phone - it may show an error"
echo "   2. Open Termux manually and run: sshd"
echo "   3. Check ~/.bashrc has the sshd autostart block"
exit 1
