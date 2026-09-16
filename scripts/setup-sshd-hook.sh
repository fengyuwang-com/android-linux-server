#!/data/data/com.termux/files/usr/bin/bash
# Install an apt/dpkg post-invoke hook that restarts sshd after package operations.
#
# Why: `pkg upgrade` replaces the sshd binary, which kills the running sshd and
# therefore your current SSH session. The cron watchdog is killed at the same
# time (it lives in the same Termux process tree), so nothing recovers it and
# you are locked out until you reach for an ADB cable.
#
# This is the layer that stops that from happening.

set -e

HOOK="$PREFIX/etc/apt/apt.conf.d/99-restart-sshd"

cat > "$HOOK" << 'EOF'
DPkg::Post-Invoke { "pgrep -f \"sshd -D\" >/dev/null 2>&1 || (sshd >/dev/null 2>&1 &)"; };
EOF

echo "✅ Installed: $HOOK"
echo
cat "$HOOK"
echo
echo "sshd will now be restarted automatically after every apt/dpkg operation."
