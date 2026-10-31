#!/bin/sh
# Builds the upload archive for extensions.gnome.org (EGO) from the extension
# sources. It only prepares the file. It does not submit anything; upload is a
# manual step for the maintainer. EGO expects metadata.json and extension.js at
# the root of the zip, with no wrapping directory.
# Usage: make-gnome-extension-zip.sh [out-dir]   (default: current directory)
set -eu

UUID="whispaste-focus@whispaste.de"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/gnome-shell-extension/$UUID"
OUT_DIR="${1:-.}"
ZIP="$OUT_DIR/$UUID.shell-extension.zip"

if [ ! -f "$SRC/metadata.json" ] || [ ! -f "$SRC/extension.js" ]; then
  echo "Extension sources not found: $SRC" >&2
  exit 1
fi
mkdir -p "$OUT_DIR"
rm -f "$ZIP"
(cd "$SRC" && zip -X -q "$ZIP" metadata.json extension.js)
echo "Built $ZIP (not submitted)"
unzip -l "$ZIP"
