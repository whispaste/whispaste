#!/usr/bin/env bash
# R-02: the .deb must not grant /dev/uinput on install. It ships the udev rule
# only as an inactive template plus the root helper and the polkit action that
# install it after the user's consent in the app. Builds a .deb from a stub
# bundle and inspects it; needs dpkg-deb (Debian/Ubuntu, CI Linux job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$WORK/bundle"
printf '#!/bin/sh\n' > "$WORK/bundle/whispaste"
bash "$ROOT/packaging/deb/build-deb.sh" "$WORK/bundle" 0.0.0 "$WORK/out" >/dev/null
DEB="$WORK/out/WhisPaste-0.0.0-linux-x64.deb"
LIST="$(dpkg-deb -c "$DEB")"

# 1. No active rule anywhere udev reads rules from.
if grep -E '\./(usr/lib|lib|etc)/udev/rules\.d/' <<<"$LIST"; then
  fail "the package installs an active udev rule"
fi
mode_of() { awk -v p="./$1" '$6 == p { print $1 }' <<<"$LIST"; }
[ "$(mode_of usr/share/whispaste/udev/71-whispaste-uinput.rules)" = "-rw-r--r--" ] ||
  fail "rule template missing or not 0644"
[ "$(mode_of usr/libexec/whispaste/uinput-access)" = "-rwxr-xr-x" ] ||
  fail "root helper missing or not 0755"
[ "$(mode_of usr/share/polkit-1/actions/de.whispaste.uinput.policy)" = "-rw-r--r--" ] ||
  fail "polkit action missing or not 0644"

# 2. The rule grants the active session only, never a group (decision 4a).
RULE="$ROOT/packaging/linux/71-whispaste-uinput.rules"
grep -v '^#' "$RULE" | grep -q 'TAG+="uaccess"' || fail "rule lost uaccess"
if grep -v '^#' "$RULE" | grep -q 'GROUP='; then fail "rule still grants a group"; fi

# 3. Maintainer scripts: nothing installs the rule; removal revokes it.
dpkg-deb -e "$DEB" "$WORK/ctrl"
# (It may test for the user's rule; it must not write one.)
if grep -v '^#' "$WORK/ctrl/postinst" |
  grep -qE '(install |cp |tee |ln |>).*rules\.d'; then
  fail "postinst installs a rule"
fi
grep -q '/usr/libexec/whispaste/uinput-access disable' "$WORK/ctrl/prerm" ||
  fail "prerm does not revoke the grant on removal"

# 4. The helper takes exactly enable|disable|status and pins its paths.
HELPER="$ROOT/packaging/linux/whispaste-uinput-access"
set +e
sh "$HELPER" --rule=/tmp/x >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] || fail "helper accepted an unknown argument (rc $rc)"
grep -q '^PATH=/usr/sbin:/usr/bin:/sbin:/bin$' "$HELPER" || fail "helper PATH not pinned"
if grep -nE '\$\{?(HOME|XDG_[A-Z_]+|TMPDIR|RULE_DIR)' "$HELPER"; then
  fail "helper reads a path from the environment"
fi
if command -v shellcheck >/dev/null 2>&1; then shellcheck -s sh "$HELPER"; fi

# 5. The polkit action asks for an admin password (kept briefly, 3a) and
#    runs only the fixed helper.
POLICY="$ROOT/packaging/linux/de.whispaste.uinput.policy"
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$POLICY"; fi
grep -q '<allow_active>auth_admin_keep</allow_active>' "$POLICY" || fail "not auth_admin_keep"
grep -q '<allow_any>no</allow_any>' "$POLICY" || fail "allow_any not no"
grep -q '<allow_inactive>no</allow_inactive>' "$POLICY" || fail "allow_inactive not no"
grep -q 'org.freedesktop.policykit.exec.path">/usr/libexec/whispaste/uinput-access<' "$POLICY" ||
  fail "exec.path not pinned to the helper"

# 6. enable/disable logic, run as a copy with its fixed paths moved into the
#    work dir and stubbed system tools (no root, no real /dev/uinput).
FAKE="$WORK/fake"
mkdir -p "$FAKE/bin" "$FAKE/share" "$FAKE/rules.d" "$FAKE/modules"
cp "$RULE" "$FAKE/share/71-whispaste-uinput.rules"
: > "$FAKE/uinput"
printf '#!/bin/sh\necho "modprobe $*" >> "%s/calls"\n' "$FAKE" > "$FAKE/bin/modprobe"
# `udevadm info` prints the device properties the case under test sets.
cat > "$FAKE/bin/udevadm" <<STUB
#!/bin/sh
echo "udevadm \$*" >> "$FAKE/calls"
[ "\$1" = info ] && cat "$FAKE/props"
exit 0
STUB
: > "$FAKE/props"
printf '#!/bin/sh\necho "setfacl $*" >> "%s/calls"\n' "$FAKE" > "$FAKE/bin/setfacl"
chmod +x "$FAKE/bin/"*
# The id -u expression is matched literally, not expanded.
# shellcheck disable=SC2016
sed -e "s|^PATH=.*|PATH=$FAKE/bin:/usr/bin:/bin|" \
  -e "s|/usr/share/whispaste/udev|$FAKE/share|" \
  -e "s|/etc/udev/rules.d|$FAKE/rules.d|" \
  -e "s|/etc/modules-load.d|$FAKE/modules|" \
  -e "s|^DEVICE=.*|DEVICE=$FAKE/uinput|" \
  -e 's|"$(id -u)"|0|' "$HELPER" > "$FAKE/helper"
if sh "$FAKE/helper" status; then fail "status reports a rule before enable"; fi
sh "$FAKE/helper" enable
cmp -s "$RULE" "$FAKE/rules.d/71-whispaste-uinput.rules" || fail "enable did not install the rule"
sh "$FAKE/helper" status || fail "status misses the installed rule"
grep -q 'udevadm trigger' "$FAKE/calls" || fail "enable did not trigger udev"
: > "$FAKE/calls"
PKEXEC_UID=1234 sh "$FAKE/helper" disable
[ ! -e "$FAKE/rules.d/71-whispaste-uinput.rules" ] || fail "disable left the rule"
[ ! -e "$FAKE/modules/whispaste-uinput.conf" ] || fail "disable left the module entry"
grep -q "setfacl -x u:1234 $FAKE/uinput" "$FAKE/calls" || fail "disable kept the session ACL"
: > "$FAKE/calls"
PKEXEC_UID='1;id' sh "$FAKE/helper" disable
if grep -q setfacl "$FAKE/calls"; then fail "disable used a non-numeric PKEXEC_UID"; fi

# 7. The uaccess check reads CURRENT_TAGS: TAGS is sticky since systemd 247
#    and still lists our tag after the rule is gone.
revokes() {
  printf '%b' "$1" > "$FAKE/props"
  : > "$FAKE/calls"
  PKEXEC_UID=1234 sh "$FAKE/helper" disable
  grep -q setfacl "$FAKE/calls"
}
revokes 'TAGS=:seat:uaccess:\nCURRENT_TAGS=:seat:\n' ||
  fail "a sticky TAGS entry kept the session ACL"
if revokes 'TAGS=:uaccess:\nCURRENT_TAGS=:uaccess:\n'; then
  fail "revoked although another rule tags the device uaccess"
fi
if revokes 'TAGS=:uaccess:\n'; then
  fail "revoked on old udev (TAGS only) although the device is tagged"
fi

# 8. postinst on upgrade drops the ACL the old install-time rule left,
#    not on a fresh install and not when the user already agreed.
sed -e "s|^DEVICE=.*|DEVICE=$FAKE/uinput|" \
  -e "s|/etc/udev/rules.d|$FAKE/rules.d|" "$WORK/ctrl/postinst" > "$FAKE/postinst"
postinst_clears() {
  printf 'TAGS=:uaccess:\nCURRENT_TAGS=:seat:\n' > "$FAKE/props"
  : > "$FAKE/calls"
  PATH="$FAKE/bin:$PATH" sh "$FAKE/postinst" configure "$1"
  grep -q "setfacl -b $FAKE/uinput" "$FAKE/calls"
}
postinst_clears 1.2.67 || fail "upgrade kept the stale session ACL"
if postinst_clears ''; then fail "fresh install touched the ACL"; fi
cp "$RULE" "$FAKE/rules.d/71-whispaste-uinput.rules"
if postinst_clears 1.2.67; then fail "upgrade dropped an agreed grant"; fi
rm "$FAKE/rules.d/71-whispaste-uinput.rules"

echo "deb uinput consent: ok"
