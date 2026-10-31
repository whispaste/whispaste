#!/bin/sh
# Removes the udev rule install-uinput-rule.sh installed, so /dev/uinput is
# no longer writable for the desktop session. Shipped in the Linux tarball.
# Run once: sudo ./uninstall-uinput-rule.sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0" >&2
  exit 1
fi

rm -f /etc/udev/rules.d/71-whispaste-uinput.rules \
  /etc/modules-load.d/whispaste-uinput.conf
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=misc --sysname-match=uinput || true
if [ -n "${SUDO_UID:-}" ] && [ -e /dev/uinput ]; then
  setfacl -x "u:$SUDO_UID" /dev/uinput 2>/dev/null || true
fi
echo "Done. Auto-Paste now copies the text only; log out and back in to be sure."
