#!/bin/sh
# Installs the udev rule that lets WhisPaste's Auto-Paste type Ctrl+V through
# /dev/uinput. While it is installed, every program in the desktop session can
# create virtual input; the app explains that before it shows this command
# (R-02). Shipped next to the rule in the Linux tarball; the .deb uses its
# polkit helper instead. Undo with uninstall-uinput-rule.sh.
# Run once: sudo ./install-uinput-rule.sh
set -eu

RULE="71-whispaste-uinput.rules"
SRC="$(dirname "$0")/$RULE"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0" >&2
  exit 1
fi
if [ ! -f "$SRC" ]; then
  echo "$RULE not found next to this script." >&2
  exit 1
fi

install -m644 "$SRC" "/etc/udev/rules.d/$RULE"
modprobe uinput 2>/dev/null || true
printf 'uinput\n' > /etc/modules-load.d/whispaste-uinput.conf
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=misc --sysname-match=uinput || true
echo "Done. Restart WhisPaste; if Auto-Paste still falls back to the clipboard, log out and back in once."
