#!/usr/bin/env bash
# Refreshes assets/tls/mozilla-cacert.pem from curl.se (Mozilla root store).
# Usage: bash scripts/update-mozilla-cacert.sh
# Downloads the bundle and its published SHA-256, refuses a mismatch, requires
# the three roots the Windows TLS fix depends on, then prints the lines to
# update in assets/tls/NOTICE.md. Run before each release, then commit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$root/assets/tls/mozilla-cacert.pem"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -sSfL -o "$tmp/cacert.pem" https://curl.se/ca/cacert.pem
curl -sSfL -o "$tmp/cacert.pem.sha256" https://curl.se/ca/cacert.pem.sha256

expected="$(awk '{print $1}' "$tmp/cacert.pem.sha256")"
actual="$(shasum -a 256 "$tmp/cacert.pem" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
  echo "SHA-256 mismatch: published $expected, downloaded $actual" >&2
  exit 1
fi

for name in "Amazon Root CA 1" "Starfield Services Root Certificate Authority - G2" "ISRG Root X1"; do
  if ! grep -q "^$name\$" "$tmp/cacert.pem"; then
    echo "required root missing: $name" >&2
    exit 1
  fi
done

cp "$tmp/cacert.pem" "$target"
version="$(grep -m1 '^## Certificate data from Mozilla as of' "$target" | sed 's/^## Certificate data from Mozilla as of: //')"
count="$(grep -c 'BEGIN CERTIFICATE' "$target")"
echo "Updated $target"
echo "Update assets/tls/NOTICE.md:"
echo "  Version: \"Certificate data from Mozilla as of: $version\""
echo "  Certificates: $count"
echo "  SHA-256: \`$actual\`"
