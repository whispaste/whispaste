/// Focus sources that ask the compositor over the session bus: the optional
/// WhisPaste GNOME Shell extension and KWin scripting (KDE Plasma).
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/logging/app_logger.dart';
import 'focused_target.dart';

final _log = AppLogger('FocusedTarget');

/// How long one D-Bus lookup may take before the source reports no target.
/// KWin needs a script load, run and callback, so this is wider than IPC.
const focusedTargetDbusTimeout = Duration(milliseconds: 500);

/// The WhisPaste GNOME Shell extension (`whispaste-focus@whispaste.de`,
/// packaging/linux/gnome-shell-extension/). GNOME keeps the focused window
/// to itself under Wayland (Introspect answers AccessDenied, Eval is locked),
/// so without the extension GNOME has no focus source at all.
class GnomeShellFocusSource implements FocusedTargetSource {
  GnomeShellFocusSource(this._client);

  static const busName = 'de.whispaste.ShellFocus';
  static const objectPath = '/de/whispaste/ShellFocus';
  static const interfaceName = 'de.whispaste.ShellFocus1';

  final DBusClient _client;

  @override
  String get name => 'gnome-extension';

  /// Whether the extension is running in this session (owns its bus name).
  Future<bool> isAvailable() async {
    try {
      return await _client
          .nameHasOwner(busName)
          .timeout(focusedTargetDbusTimeout);
    } on Object catch (e) {
      // No session bus or no answer: treat the extension as missing.
      _log.debug('GNOME focus extension state unknown', e);
      return false;
    }
  }

  @override
  Future<FocusedTarget?> focusedTarget() async {
    try {
      final reply = await _client
          .callMethod(
            destination: busName,
            path: DBusObjectPath(objectPath),
            interface: interfaceName,
            name: 'GetFocusedWindow',
            replySignature: DBusSignature('a{sv}'),
            noAutoStart: true,
          )
          .timeout(focusedTargetDbusTimeout);
      return targetFromReply(reply.returnValues.single.asStringVariantDict());
    } on Object catch (e) {
      // Extension missing, disabled or slow: target unknown.
      _log.debug('GNOME focus extension did not answer', e);
      return null;
    }
  }

  /// The extension's `a{sv}` answer; an empty dict means nothing has focus.
  static FocusedTarget? targetFromReply(Map<String, DBusValue> values) {
    String? text(String key) {
      final value = values[key];
      return value is DBusString ? value.value : null;
    }

    final x11 = text('client_type') == 'x11';
    return FocusedTarget.from(
      x11
          ? [text('wm_class_instance'), text('wm_class'), text('app_id')]
          : [text('app_id'), text('wm_class'), text('wm_class_instance')],
      source: 'gnome-extension',
      clientType: switch (text('client_type')) {
        'x11' => FocusedClientType.x11,
        'wayland' => FocusedClientType.wayland,
        _ => FocusedClientType.unknown,
      },
    );
  }
}

/// KWin (Plasma 5 and 6): loads a two-line KWin script that calls back with
/// the active window's names, runs it once and unloads it. KWin has no
/// method that returns the active window directly; this is the route
/// kdotool and similar tools take.
class KWinFocusSource implements FocusedTargetSource {
  KWinFocusSource(this._client, {Directory? scriptDirectory})
    : _scriptDirectory = scriptDirectory ?? Directory.systemTemp;

  static const reportPath = '/de/whispaste/KWinFocus';
  static const reportInterface = 'de.whispaste.KWinFocus';
  static const pluginName = 'whispaste-focus';

  final DBusClient _client;
  final Directory _scriptDirectory;
  _ReportObject? _report;
  File? _script;
  Future<void> _queue = Future.value();

  @override
  String get name => 'kwin';

  @override
  Future<FocusedTarget?> focusedTarget() {
    // One lookup at a time: the script and its plugin name are shared.
    final result = _queue.then((_) => _lookup());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<FocusedTarget?> _lookup() async {
    try {
      return await _run().timeout(focusedTargetDbusTimeout);
    } on Object catch (e) {
      // KWin missing, scripting disabled or slow: target unknown.
      _log.debug('KWin did not report the active window', e);
      return null;
    } finally {
      await _unload();
    }
  }

  Future<FocusedTarget?> _run() async {
    final report = _report ??= _ReportObject();
    if (report.client == null) await _client.registerObject(report);
    final script = await _writeScript();
    await _unload();
    final load = await _callKWin(
      DBusObjectPath('/Scripting'),
      'org.kde.kwin.Scripting',
      'loadScript',
      [DBusString(script.path), const DBusString(pluginName)],
    );
    final id = load.returnValues.single.asInt32();
    if (id < 0) return null;
    final answer = report.next();
    await _runScript(id);
    return answer;
  }

  /// Plasma 6 exports scripts at `/Scripting/Script<id>`, Plasma 5 at `/<id>`.
  Future<void> _runScript(int id) async {
    try {
      await _callKWin(
        DBusObjectPath('/Scripting/Script$id'),
        'org.kde.kwin.Script',
        'run',
      );
    } on DBusMethodResponseException {
      await _callKWin(DBusObjectPath('/$id'), 'org.kde.kwin.Script', 'run');
    }
  }

  Future<void> _unload() async {
    try {
      await _callKWin(
        DBusObjectPath('/Scripting'),
        'org.kde.kwin.Scripting',
        'unloadScript',
        [const DBusString(pluginName)],
      );
    } on Object catch (e) {
      // Nothing loaded or KWin gone; the next lookup starts clean anyway.
      _log.debug('KWin script not unloaded', e);
    }
  }

  Future<DBusMethodSuccessResponse> _callKWin(
    DBusObjectPath path,
    String interface,
    String method, [
    List<DBusValue> values = const [],
  ]) => _client.callMethod(
    destination: 'org.kde.KWin',
    path: path,
    interface: interface,
    name: method,
    values: values,
    noAutoStart: true,
  );

  Future<File> _writeScript() async {
    final existing = _script;
    if (existing != null && existing.existsSync()) return existing;
    final file = File('${_scriptDirectory.path}/whispaste-kwin-focus-$pid.js');
    await file.writeAsString(kwinFocusScript(_client.uniqueName));
    return _script = file;
  }
}

/// The KWin script: Plasma 6 names the active window `activeWindow`,
/// Plasma 5 `activeClient`. It sends names only, never the title.
String kwinFocusScript(String callbackName) =>
    '''
const w = workspace.activeWindow !== undefined ? workspace.activeWindow : workspace.activeClient;
callDBus("$callbackName", "${KWinFocusSource.reportPath}", "${KWinFocusSource.reportInterface}", "Report", w ? String(w.resourceName || "") : "", w ? String(w.resourceClass || "") : "", w ? String(w.desktopFileName || "") : "");
''';

/// The target from KWin's names for the active window. KWin exposes no
/// client type to scripts, and its `_NET_ACTIVE_WINDOW` points at an
/// internal window while a Wayland window has focus, so the type is read
/// from the names (checked against kwin_wayland 6 with GTK 3/4 probes):
/// - Wayland: resourceClass is the app id and equals desktopFileName;
///   resourceName is only the binary (`python3.14`), so it comes last.
/// - X11: resourceName is the WM_CLASS instance, resourceClass the class.
@visibleForTesting
FocusedTarget? kwinTarget(
  String resourceName,
  String resourceClass,
  String desktopFileName,
) {
  final wayland =
      desktopFileName.isNotEmpty &&
      desktopFileName.toLowerCase() == resourceClass.toLowerCase();
  return FocusedTarget.from(
    wayland
        ? [resourceClass, resourceName]
        : [resourceName, resourceClass, desktopFileName],
    source: 'kwin',
    clientType: wayland ? FocusedClientType.wayland : FocusedClientType.x11,
  );
}

class _ReportObject extends DBusObject {
  _ReportObject() : super(DBusObjectPath(KWinFocusSource.reportPath));

  Completer<FocusedTarget?>? _pending;

  Future<FocusedTarget?> next() => (_pending = Completer()).future;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != KWinFocusSource.reportInterface ||
        methodCall.name != 'Report' ||
        methodCall.signature != DBusSignature('sss')) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    final names = [for (final v in methodCall.values) v.asString()];
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(kwinTarget(names[0], names[1], names[2]));
    }
    return DBusMethodSuccessResponse();
  }
}
