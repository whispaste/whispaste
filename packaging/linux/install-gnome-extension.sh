#!/bin/sh
# Installs the optional WhisPaste Focus GNOME Shell extension for the current
# user and enables it. The extension tells WhisPaste which window has focus,
# which GNOME on Wayland does not reveal otherwise. Nothing is installed
# system-wide and nothing needs root. Shipped next to the extension directory
# in the Linux tarball; the .deb installs the same files system-wide, disabled.
# Run as the desktop user: ./install-gnome-extension.sh
set -eu

UUID="whispaste-focus@whispaste.de"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/gnome-shell-extension/$UUID"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST_ROOT="$DATA_HOME/gnome-shell/extensions"

if [ "$(id -u)" -eq 0 ]; then
  echo "Please run as your desktop user, not as root." >&2
  exit 1
fi
if [ ! -f "$SRC/metadata.json" ] || [ ! -f "$SRC/extension.js" ]; then
  echo "Extension files not found next to this script ($SRC)." >&2
  exit 1
fi
if ! command -v gnome-extensions >/dev/null 2>&1; then
  echo "gnome-extensions not found. This extension needs GNOME Shell 45 to 50." >&2
  exit 1
fi

mkdir -p "$DEST_ROOT"
rm -rf "${DEST_ROOT:?}/$UUID"
cp -r "$SRC" "$DEST_ROOT/$UUID"
echo "Copied the extension to $DEST_ROOT/$UUID"

if gnome-extensions enable "$UUID" 2>/dev/null; then
  echo "Enabled $UUID."
else
  echo "Could not enable $UUID yet. GNOME Shell may not have picked up the new files."
  echo "Run: gnome-extensions enable $UUID"
fi

echo "On Wayland, log out and back in once so GNOME Shell loads the extension."
echo "Check afterwards: gnome-extensions info $UUID"
