/// macOS in-app update swap.
///
/// The update machinery (GitHub check, semver, DMG download) already exists in
/// [UpdateNotifier]. This module supplies the final step Windows already has:
/// replace the running app with the downloaded version. macOS cannot overwrite
/// a running `.app`, so a detached shell helper waits for WhisPaste to exit,
/// swaps the new bundle in from the mounted DMG (atomically, with a pre-flight
/// guard and an admin-escalation branch for non-writable targets), then
/// relaunches. This mirrors the Windows installer flow (launch installer →
/// `exit(0)`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the `.app` bundle the running executable lives in, or `null` when
/// not running from a bundle (dev/test/non-bundle context) — in which case the
/// caller falls back to merely opening the DMG.
///
/// The target is derived from the running executable, NOT hard-coded to
/// `/Applications`, so a bundle the user deliberately placed elsewhere updates
/// in place.
String? resolveMacAppBundlePath() {
  final exe = Platform.resolvedExecutable;
  const marker = '.app/Contents/MacOS/';
  final idx = exe.indexOf(marker);
  if (idx < 0) return null;
  final bundle = exe.substring(0, idx + '.app'.length);
  if (!bundle.endsWith('.app')) return null;
  if (!Directory(bundle).existsSync()) return null;
  return bundle;
}

/// Single-quotes [s] for safe embedding as a POSIX shell literal.
String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Builds the detached helper shell script. Pure function so it can be unit
/// tested and verified against a real DMG without mounting in the test.
///
/// The script: waits for [parentPid] to exit → mounts [dmgPath] read-only →
/// guards that it contains a valid `WhisPaste.app` → stages a copy next to
/// [targetBundlePath] and renames it into place atomically (writable target
/// directly, else once via `osascript … with administrator privileges`) →
/// detaches → relaunches. Any failure before the atomic rename leaves the
/// existing install untouched.
String buildMacUpdateHelperScript({
  required int parentPid,
  required String dmgPath,
  required String targetBundlePath,
  required String logPath,
}) {
  final dmg = _shq(dmgPath);
  final target = _shq(targetBundlePath);
  final log = _shq(logPath);
  return '''#!/bin/bash
# WhisPaste macOS in-app update helper (generated at runtime). Do not edit.
set -uo pipefail
PARENT_PID=$parentPid
DMG=$dmg
TARGET=$target
LOG=$log
exec >>"\$LOG" 2>&1
echo "[wp-update] start pid=\$PARENT_PID target=\$TARGET"

# 1. Wait for WhisPaste to exit (max ~20s).
for _ in \$(seq 1 100); do
  kill -0 "\$PARENT_PID" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "\$PARENT_PID" 2>/dev/null; then
  echo "[wp-update] ERROR: app still running — abort, nothing touched"
  exit 11
fi

# 2. Mount the DMG read-only.
PLIST="\$(mktemp)"
if ! hdiutil attach -nobrowse -readonly -plist "\$DMG" >"\$PLIST" 2>&1; then
  echo "[wp-update] ERROR: mount failed — abort, nothing touched"
  exit 12
fi
MNT="\$(grep -o '/Volumes/[^<]*' "\$PLIST" | head -1)"
echo "[wp-update] mounted at \$MNT"
detach() {
  hdiutil detach "\$MNT" >/dev/null 2>&1 || { sleep 1; hdiutil detach -force "\$MNT" >/dev/null 2>&1; }
}

SRC="\$MNT/WhisPaste.app"
# 3. Pre-flight bundle guard — never overwrite a working install for a bad DMG.
if [ ! -d "\$SRC" ] || [ ! -f "\$SRC/Contents/Info.plist" ]; then
  echo "[wp-update] ERROR: invalid bundle in DMG — abort, nothing touched"
  detach
  exit 13
fi

# 4. Stage + atomic swap as a self-contained inner script with concrete paths,
#    so it runs identically whether direct or under one admin prompt.
STAGE="\${TARGET}.wp-new-\$\$"
BACKUP="\${TARGET}.wp-old-\$\$"
INNER="\$(mktemp /tmp/wp-swap.XXXXXX)"
cat >"\$INNER" <<WPINNER
#!/bin/sh
set -e
rm -rf "\$STAGE" "\$BACKUP"
/usr/bin/ditto "\$SRC" "\$STAGE"
/usr/bin/xattr -dr com.apple.quarantine "\$STAGE" 2>/dev/null || true
mv "\$TARGET" "\$BACKUP"
mv "\$STAGE" "\$TARGET"
rm -rf "\$BACKUP"
WPINNER
chmod +x "\$INNER"

# 5. Run the swap. Writable target → directly; otherwise escalate once. On
#    cancel/failure the original install is left untouched (atomic rename
#    never started).
PARENT_DIR="\$(dirname "\$TARGET")"
if [ -w "\$PARENT_DIR" ] && { [ ! -e "\$TARGET" ] || [ -w "\$TARGET" ]; }; then
  echo "[wp-update] writable target — direct swap"
  if ! /bin/sh "\$INNER"; then
    echo "[wp-update] ERROR: swap failed"; detach; rm -f "\$INNER"; exit 14
  fi
else
  echo "[wp-update] non-writable target — escalating via admin prompt"
  if ! /usr/bin/osascript -e "do shell script \\"/bin/sh \$INNER\\" with administrator privileges"; then
    echo "[wp-update] ERROR: escalation declined/failed — install untouched"
    detach; rm -f "\$INNER"; exit 15
  fi
fi
rm -f "\$INNER"
echo "[wp-update] swap ok"

# 6. Detach and relaunch as the user (never root).
detach
/usr/bin/open "\$TARGET"
echo "[wp-update] done"
''';
}

/// Performs the macOS update swap by spawning the detached helper.
abstract class MacUpdateInstaller {
  /// Writes the helper and launches it detached. Returns once spawned; the
  /// caller then exits so the helper can replace the running bundle.
  Future<void> swap({
    required String dmgPath,
    required String targetBundlePath,
  });
}

/// Production [MacUpdateInstaller]: writes the generated helper to a temp dir,
/// makes it executable, and launches it detached.
class DefaultMacUpdateInstaller implements MacUpdateInstaller {
  const DefaultMacUpdateInstaller();

  @override
  Future<void> swap({
    required String dmgPath,
    required String targetBundlePath,
  }) async {
    final dir = await Directory.systemTemp.createTemp('wp-update-helper');
    final scriptPath = p.join(dir.path, 'wp-update-helper.sh');
    final logPath = p.join(dir.path, 'wp-update.log');
    await File(scriptPath).writeAsString(
      buildMacUpdateHelperScript(
        parentPid: pid,
        dmgPath: dmgPath,
        targetBundlePath: targetBundlePath,
        logPath: logPath,
      ),
    );
    await Process.run('chmod', ['+x', scriptPath]);
    await Process.start('/bin/bash', [
      scriptPath,
    ], mode: ProcessStartMode.detached);
  }
}
