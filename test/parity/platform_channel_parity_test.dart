// Platform-channel parity guard (PAR-guard, see internal-notes).
//
// Channel level: every WhisPaste-owned channel name used in lib/
// (`com.whispaste.*`, `whispaste/*`) must be registered by the native runner
// on each desktop platform, or be listed in [_allowlist] with a reason.
//
// Method level (DEV-254): every method name Dart invokes on a channel must
// have a native handler on each platform, or an entry in [_methodAllowlist].
// Dart calls are attributed to the channel object they go through (a
// MethodChannel declaration in the same file or in an imported file). Native
// handlers are real dispatch matches (Swift `case "x"`, C++ `method == "x"`,
// `strcmp(method, "x") == 0`), read after comments are stripped, so a name
// that only appears in a comment or a log string does not count.
//
// Static check: it does not prove a handler works; that is the runtime audit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _platforms = ['macos', 'windows', 'linux'];

/// Source extensions scanned per native platform.
const _nativeExtensions = <String, Set<String>>{
  'macos': {'.swift', '.m', '.mm', '.h'},
  'windows': {'.cpp', '.cc', '.h'},
  'linux': {'.cc', '.cpp', '.h'},
};

/// Literal names that match the channel pattern but are not channels.
const _notChannels = <String, String>{
  'com.whispaste.whispaste':
      'Old bundle identifier (bundle_id_migration_adapters.dart), not a channel.',
  'com.whispaste.app':
      'Package identifier passed to launch_at_startup (autostart_service.dart), not a channel.',
};

/// Intentional channel-level gaps: channel -> platform -> reason.
const _allowlist = <String, Map<String, String>>{
  'com.whispaste.app_lifecycle': {
    'windows':
        'macOS-only (NSApplication lifecycle). MacOSLifecycleChannel returns early unless Platform.isMacOS.',
    'linux':
        'macOS-only (NSApplication lifecycle). MacOSLifecycleChannel returns early unless Platform.isMacOS.',
  },
  'com.whispaste.attention': {
    'macos':
        'macOS attention goes through com.whispaste.app_lifecycle (MacOSLifecycleChannel.requestUserAttention).',
  },
  'com.whispaste.audio_routing': {
    'windows':
        'macOS-only: AudioRoutingService.isSupported == Platform.isMacOS.',
    'linux': 'macOS-only: AudioRoutingService.isSupported == Platform.isMacOS.',
  },
  'whispaste/settings_window': {
    'windows':
        'macOS-only: placing the window beside System Settings after the Accessibility deep-link; placeBesideSystemSettings returns false unless Platform.isMacOS.',
    'linux':
        'macOS-only: placing the window beside System Settings after the Accessibility deep-link; placeBesideSystemSettings returns false unless Platform.isMacOS.',
  },
  'whispaste/permission_helper': {
    'windows':
        'Onboarding accessibility drag panel (NSPanel docked to System Settings). Windows needs no accessibility grant: PermissionHelperService.show answers unsupported without a channel call and the onboarding keeps its text guide (parity matrix: macOS-only by OS design).',
    'linux':
        'Onboarding accessibility drag panel (NSPanel docked to System Settings). Linux needs no accessibility grant: PermissionHelperService.show answers unsupported without a channel call and the onboarding keeps its text guide (parity matrix: macOS-only by OS design).',
  },
  'com.whispaste.bundle_id_migration': {
    'windows':
        'macOS-only one-time migration from com.whispaste.whispaste (main.dart:325).',
    'linux':
        'macOS-only one-time migration from com.whispaste.whispaste (main.dart:325).',
  },
  'com.whispaste.file_dialog': {
    'macos':
        'Linux-only: file_selector_linux shows no title and English buttons, so LinuxFileSelector is installed only on Linux (service_bootstrap.dart); macOS keeps file_selector_macos.',
    'windows':
        'Linux-only: file_selector_linux shows no title and English buttons, so LinuxFileSelector is installed only on Linux (service_bootstrap.dart); Windows keeps file_selector_windows.',
  },
  'com.whispaste.modifier_monitor': {
    'windows':
        'ModifierKeyMonitor (Input Monitoring) is macOS-only: HotkeyService starts it only on macOS. Windows uses the same channel through watchModifier (RawInput in keyboard_monitor) for rightControl, rightAlt and rightMeta.',
    'linux':
        'ModifierKeyMonitor (Input Monitoring) is macOS-only: HotkeyService starts it only on macOS. Linux uses the same channel through watchModifier (XInput2 in keyboard_monitor, X11 only) for rightControl, rightAlt and rightMeta.',
  },
  'com.whispaste.keyboard_monitor': {
    'macos':
        'macOS key-up comes from hotkey_manager (HotkeyService.supportsKeyUp); the channel is used only on Windows and Linux.',
  },
  'com.whispaste.secure_bookmark': {
    'windows':
        'MAS sandbox only: SecureBookmarkService.isSupported == Platform.isMacOS.',
    'linux':
        'MAS sandbox only: SecureBookmarkService.isSupported == Platform.isMacOS.',
  },
  'com.whispaste.support_store': {
    'linux':
        'No store purchase on Linux: resolveSupportStoreBridge returns UnavailableSupportStoreBridge.',
  },
};

/// Intentional method-level gaps: channel -> method -> platform -> reason.
const _methodAllowlist = <String, Map<String, Map<String, String>>>{
  'com.whispaste.desktop_paste': {
    'clipboardReadDenied': {
      'windows':
          'macOS pasteboard privacy (NSPasteboard accessBehavior). Windows has no such restriction, so the probe is never sent there; a MissingPluginException reads as not denied.',
      'linux':
          'macOS pasteboard privacy (NSPasteboard accessBehavior). Linux has no such restriction, so the probe is never sent there; a MissingPluginException reads as not denied.',
    },
    'repairTccEntries': {
      'windows':
          'macOS TCC permission repair. The Windows controller reports it unsupported and never reaches the native host.',
      'linux':
          'macOS TCC permission repair. The Linux controller reports it unsupported and never reaches the native host.',
    },
    'sendUndoShortcut': {
      'windows':
          'Clipboard-only undo: Windows has no undo keystroke path, so undo always copies the original text to the clipboard.',
      'linux':
          'Clipboard-only undo: Linux has no undo keystroke path, so undo always copies the original text to the clipboard.',
    },
    'secureInputState': {
      'windows':
          'macOS-only system flag (IsSecureEventInputEnabled). Windows has no such flag: the controller gets MissingPluginException and reports unsupported, so the paste runs as before (W-E1, CONTEXT.md §2.7).',
      'linux':
          'macOS-only system flag (IsSecureEventInputEnabled). Linux has no such flag: the controller gets MissingPluginException and reports unsupported, so the paste runs as before (W-E1, CONTEXT.md §2.7).',
    },
    'secureInputHolder': {
      'windows':
          'macOS-only: the session dictionary names the app holding secure input (F35-8). Windows has no such holder: MissingPluginException, the notice stays generic and the skip never happens there (no secure input signal).',
      'linux':
          'macOS-only: the session dictionary names the app holding secure input (F35-8). Linux has no such holder: MissingPluginException, the notice stays generic and the skip never happens there (no secure input signal).',
    },
  },
  'com.whispaste.floating_button': {
    'getCapabilities': {
      'macos':
          'Linux-only probe: floating_button_support_provider.dart asks for the GDK backend only when the target platform is Linux. macOS never sends it and has no X11 backend to report.',
      'windows':
          'Linux-only probe: floating_button_support_provider.dart asks for the GDK backend only when the target platform is Linux. Windows never sends it and has no X11 backend to report.',
    },
  },
  'com.whispaste.support_store': {
    'hasVerifiedSupportPurchase': {
      'windows':
          'Only the macOS StoreKit bridge calls this on the channel. The Windows bridge reads the verified state from SharedPreferences and never invokes the channel.',
    },
  },
  'com.whispaste.keyboard_monitor': {
    'resolveLayoutLabel': {
      'linux':
          'Windows-only key resolution: resolveWindowsKey returns before invoking the channel on other platforms (win_layout_label.dart).',
    },
    'resolveLiveVirtualKey': {
      'linux':
          'Windows-only key resolution: resolveWindowsKey returns before invoking the channel on other platforms (win_layout_label.dart).',
    },
  },
};

final _channelLiteral = RegExp(
  r"""['"]((?:com\.whispaste\.[a-z_]+)|(?:whispaste/[a-z_]+))['"]""",
);

// ---------------------------------------------------------------------------
// Pure parsing helpers (also exercised by the negative fixtures below).
// ---------------------------------------------------------------------------

/// Removes `//` and `/* */` comments outside string literals. Newlines are
/// kept so line structure survives. Triple-quoted strings are kept whole.
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (src.startsWith('"""', i) || src.startsWith("'''", i)) {
      final quote = src.substring(i, i + 3);
      final end = src.indexOf(quote, i + 3);
      final stop = end < 0 ? src.length : end + 3;
      out.write(src.substring(i, stop));
      i = stop;
      continue;
    }
    final c = src[i];
    if (c == '"' || c == "'") {
      final start = i;
      i++;
      while (i < src.length && src[i] != c && src[i] != '\n') {
        if (src[i] == '\\') i++;
        i++;
      }
      i = i < src.length ? i + 1 : src.length;
      out.write(src.substring(start, i));
      continue;
    }
    if (src.startsWith('//', i)) {
      final end = src.indexOf('\n', i);
      i = end < 0 ? src.length : end;
      continue;
    }
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      final stop = end < 0 ? src.length : end + 2;
      for (final ch in src.substring(i, stop).split('')) {
        if (ch == '\n') out.write('\n');
      }
      i = stop;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

final _quotedName = RegExp(r'"([A-Za-z]+)"');
final _swiftCaseClause = RegExp(
  r'\bcase\s+((?:"[A-Za-z]+"\s*,\s*)*"[A-Za-z]+")\s*:',
);
final _nativeCompare = RegExp(
  r'\bmethod(?:_name\(\))?\s*==\s*"([A-Za-z]+)"'
  r'|"([A-Za-z]+)"\s*==\s*method\b'
  r'|\bmethod_name\(\)\.compare\(\s*"([A-Za-z]+)"\s*\)\s*==\s*0'
  r'|\b(?:strcmp|g_strcmp0)\(\s*method\s*,\s*"([A-Za-z]+)"\s*\)',
);

/// Method names with a real dispatch match in one native source file, read
/// after comments are stripped.
Set<String> nativeHandlersIn(String rawSource) {
  final src = stripComments(rawSource);
  final names = <String>{};
  for (final clause in _swiftCaseClause.allMatches(src)) {
    for (final q in _quotedName.allMatches(clause.group(1)!)) {
      names.add(q.group(1)!);
    }
  }
  for (final m in _nativeCompare.allMatches(src)) {
    for (var g = 1; g <= 4; g++) {
      final name = m.group(g);
      if (name != null) names.add(name);
    }
  }
  return names;
}

/// Channel names mentioned in one native source file (comments stripped).
Set<String> channelsMentionedIn(String rawSource) {
  final src = stripComments(rawSource);
  return {for (final m in _channelLiteral.allMatches(src)) m.group(1)!}
    ..removeWhere(_notChannels.containsKey);
}

/// Matches a dispatch into a named handler: `handleX(call, ...)`.
final _callTarget = RegExp(r'\b([A-Za-z_]\w*)\(\s*call\b');

/// Index of the `}` matching the `{` at [open], ignoring braces inside string
/// literals, so a `"}"` in a handler does not end its block.
int _blockEnd(String src, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      if (c == '\\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return src.length - 1;
}

/// Cases of the named function [fn] defined in [src] (brace-matched body).
Set<String> _functionBodyHandlers(String src, String fn) {
  // Definitions only (`func fn(` on Swift, `Class::fn(` on C++), so a call
  // site such as `fn(call, ...)` is never taken for the body.
  final def = RegExp(
    '(?:\\bfunc\\s+|::)$fn\\s*\\([^)]*\\)[^{;]*\\{',
  ).firstMatch(src);
  if (def == null) return {};
  final end = _blockEnd(src, def.end - 1);
  return nativeHandlersIn(src.substring(def.end - 1, end + 1));
}

/// Native handlers per channel for one platform. Each handler block belongs to
/// the channel registered just before it. A file is cut at every WhisPaste
/// channel mention: a literal name, or a constant that holds one (declared in
/// the platform's sources). Inside a cut, the handlers are the cases written
/// there plus the cases of any named function the registration dispatches to
/// (`handleX(call, ...)`). Code before the first mention belongs to no
/// channel, so a case there cannot be credited to a later channel.
Map<String, Set<String>> nativeMethodsByChannel(Map<String, String> files) {
  final stripped = {
    for (final e in files.entries) e.key: stripComments(e.value),
  };
  final constants = <String, String>{};
  for (final src in stripped.values) {
    for (final m in _channelConstDecl.allMatches(src)) {
      constants[m.group(1)!] = m.group(2)!;
    }
  }
  final result = <String, Set<String>>{};
  stripped.forEach((_, src) {
    final mentions = <(int, String)>[];
    for (final m in _channelLiteral.allMatches(src)) {
      if (_notChannels.containsKey(m.group(1)!)) continue;
      mentions.add((m.start, m.group(1)!));
    }
    for (final m in _identifier.allMatches(src)) {
      final value = constants[m.group(0)!];
      if (value == null) continue;
      // The declaration itself is not a registration.
      if (_channelConstDecl.matchAsPrefix(src, m.start) != null) continue;
      mentions.add((m.start, value));
    }
    mentions.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 0; i < mentions.length; i++) {
      final start = mentions[i].$1;
      final end = i + 1 < mentions.length ? mentions[i + 1].$1 : src.length;
      final segment = src.substring(start, end);
      final handlers = nativeHandlersIn(segment);
      for (final m in _callTarget.allMatches(segment)) {
        handlers.addAll(_functionBodyHandlers(src, m.group(1)!));
      }
      if (handlers.isEmpty) continue;
      result.putIfAbsent(mentions[i].$2, () => <String>{}).addAll(handlers);
    }
  });
  return result;
}

final _identifier = RegExp(r'\b[A-Za-z_]\w*\b');

/// `NAME = 'com.whispaste.x'` (or double-quoted, optional type): a channel
/// constant that a MethodChannel argument may refer to.
final _channelConstDecl = RegExp(
  r'\b([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?=\s*[\x27\x22]((?:com\.whispaste\.[a-z_]+)|(?:whispaste/[a-z_]+))[\x27\x22]',
);

/// `name = [const] MethodChannel(arg)`, also `channel ?? const MethodChannel(arg)`.
/// The argument is a literal or a constant (resolved in [dartMethodsByChannel]).
final _methodChannelDecl = RegExp(
  r'([A-Za-z_]\w*)\s*=\s*(?:[^;=]*?\?\?\s*)?(?:const\s+)?MethodChannel\(\s*([^),]+?)\s*,?\s*\)',
);
final _literalInvoke = RegExp(
  r"([A-Za-z_][\w.]*)\.invoke(?:Map|List)?Method(?:<[^>]*>)?\(\s*'([A-Za-z]+)'",
);
final _variableInvoke = RegExp(
  r'([A-Za-z_][\w.]*)\.invoke(?:Map|List)?Method(?:<[^>]*>)?\(\s*[a-z]\w*\s*[,)]',
);
final _helperDecl = RegExp(r'\b([A-Za-z_]\w*)\(\s*String\s+method\b');
final _importDirective = RegExp(r"import\s+'([^']+)'");

class DartCalls {
  DartCalls(this.methods, this.unresolved);

  /// channel -> invoked method names.
  final Map<String, Set<String>> methods;

  /// Invocations whose channel could not be resolved.
  final List<String> unresolved;
}

/// Resolves the paths a Dart file imports, within [files] (keys are
/// repo-relative paths such as `lib/services/x.dart`).
Iterable<String> _importedPaths(
  String file,
  String src,
  Set<String> known,
) sync* {
  final dir = file.substring(0, file.lastIndexOf('/') + 1);
  for (final m in _importDirective.allMatches(src)) {
    final spec = m.group(1)!;
    String? resolved;
    if (spec.startsWith('package:whispaste/')) {
      resolved = 'lib/${spec.substring('package:whispaste/'.length)}';
    } else if (!spec.contains(':')) {
      resolved = Uri(path: dir).resolve(spec).path;
    }
    if (resolved != null && known.contains(resolved)) yield resolved;
  }
}

/// Attributes each Dart method call to the MethodChannel it goes through.
/// [files] maps repo-relative Dart paths to their source.
DartCalls dartMethodsByChannel(Map<String, String> files) {
  final stripped = {
    for (final e in files.entries) e.key: stripComments(e.value),
  };
  final known = files.keys.toSet();
  // Channel constants declared in any Dart file (`const x = 'com.whispaste.y'`).
  final constants = <String, String>{};
  for (final src in stripped.values) {
    for (final m in _channelConstDecl.allMatches(src)) {
      constants[m.group(1)!] = m.group(2)!;
    }
  }
  // A declaration argument is a quoted literal or a constant name.
  final declsByFile = <String, Map<String, String>>{};
  stripped.forEach((file, src) {
    final decls = <String, String>{};
    for (final m in _methodChannelDecl.allMatches(src)) {
      final arg = m.group(2)!;
      final literal = RegExp(r"^'([^']+)'$").firstMatch(arg)?.group(1);
      final value = literal ?? constants[arg.split('.').last];
      if (value != null) decls[m.group(1)!] = value;
    }
    declsByFile[file] = decls;
  });

  String? resolve(String file, String receiver) {
    final name = receiver.split('.').last;
    final local = declsByFile[file]?[name];
    if (local != null) return local;
    for (final imported in _importedPaths(file, stripped[file]!, known)) {
      final found = declsByFile[imported]?[name];
      if (found != null) return found;
    }
    return null;
  }

  final methods = <String, Set<String>>{};
  final unresolved = <String>[];
  stripped.forEach((file, src) {
    void add(String channel, String method) {
      // Third-party plugin channels (e.g. launch_at_startup) are out of scope.
      if (!_isWhispasteChannel(channel)) return;
      methods.putIfAbsent(channel, () => <String>{}).add(method);
    }

    for (final m in _literalInvoke.allMatches(src)) {
      final receiver = m.group(1)!;
      final channel = resolve(file, receiver);
      if (channel == null) {
        unresolved.add('$file: $receiver.${m.group(2)}');
      } else {
        add(channel, m.group(2)!);
      }
    }

    // Methods passed through a local helper (`helper('name')` where the
    // helper forwards its `method` parameter to invokeMethod).
    // A file without a forwarding invokeMethod (e.g. an HTTP client with a
    // `_send(String method)` helper) has no channel calls to attribute.
    final forwarded = _variableInvoke.firstMatch(src);
    if (forwarded == null) return;
    for (final helper in _helperDecl.allMatches(src).map((m) => m.group(1)!)) {
      for (final call in RegExp(
        '\\b$helper\\(\\s*\'([A-Za-z]+)\'',
      ).allMatches(src)) {
        final channel = resolve(file, forwarded.group(1)!);
        if (channel == null) {
          unresolved.add('$file: $helper(${call.group(1)})');
        } else {
          add(channel, call.group(1)!);
        }
      }
    }
  });
  return DartCalls(methods, unresolved);
}

bool _isWhispasteChannel(String name) =>
    _channelLiteral.hasMatch("'$name'") && !_notChannels.containsKey(name);

/// Files whose channel is injected at runtime (generic render hosts). Calls
/// through their channel field cannot be attributed statically. Recorded gap.
const _unresolvedAllowlist = <String, String>{
  'lib/services/modifier_key_monitor.dart':
      'The channel is injected by the constructor (tests pass a fake); the static name is _defaultChannel, so its calls are not attributed statically.',
  'lib/services/side_panel/side_panel_render_channel.dart':
      'Generic render channel: its name is injected, so calls are not attributed here; render_channel_parity_test.dart checks its methods per native host.',
  'lib/services/floating_button/floating_button_render_channel.dart':
      'Generic render channel: its name is injected, so calls are not attributed here; render_channel_parity_test.dart checks its methods per native host.',
  'lib/services/floating_overlay/overlay_render_channel.dart':
      'Generic render channel: its name is injected, so calls are not attributed here; render_channel_parity_test.dart checks its methods per native host.',
  'lib/services/snippet_picker/snippet_picker_render_channel.dart':
      'Generic render channel: its name is injected, so calls are not attributed here; render_channel_parity_test.dart checks its methods per native host.',
  'lib/services/method_channel_platform_host.dart':
      'Generic base host: the channel name is a constructor argument of each subclass, so its calls are not attributed statically.',
  'lib/services/support/mac_storekit_support_store_bridge.dart':
      'Store bridge with an injected channel: the channel name comes from the constructor, so its calls are not attributed statically.',
  'lib/services/support/windows_support_store_bridge.dart':
      'Store bridge with an injected channel: the channel name comes from the constructor, so its calls are not attributed statically.',
};

/// Problems for the method-level check. [nativeByPlatform] maps platform ->
/// channel -> handled methods.
List<String> methodProblems({
  required DartCalls dart,
  required Map<String, Map<String, Set<String>>> nativeByPlatform,
  Map<String, Map<String, Map<String, String>>> methodAllowlist = const {},
  Map<String, Map<String, String>> channelAllowlist = const {},
}) {
  final problems = <String>[
    for (final u in dart.unresolved)
      if (!_unresolvedAllowlist.containsKey(u.split(':').first))
        'unresolved call: $u',
  ];
  final channels = dart.methods.keys.toList()..sort();
  for (final channel in channels) {
    for (final method in dart.methods[channel]!.toList()..sort()) {
      for (final platform in _platforms) {
        // Platform-only channels are covered at channel level.
        if (channelAllowlist[channel]?.containsKey(platform) ?? false) continue;
        final handled =
            nativeByPlatform[platform]?[channel]?.contains(method) ?? false;
        final allowed = methodAllowlist[channel]?[method]?[platform] != null;
        if (!handled && !allowed) {
          problems.add(
            '$channel.$method has no $platform native handler and no '
            'allowlist entry',
          );
        }
        if (handled && allowed) {
          problems.add(
            '$channel.$method is handled on $platform; remove its '
            'allowlist entry',
          );
        }
      }
    }
  }
  return problems;
}

// ---------------------------------------------------------------------------
// Repository scan.
// ---------------------------------------------------------------------------

Iterable<String> _filesUnder(String dir, Set<String> extensions) sync* {
  final root = Directory(dir);
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    if (extensions.any(path.endsWith)) yield path;
  }
}

/// Native runner plus package native folders for [platform].
Iterable<String> _nativeFiles(String platform) sync* {
  final extensions = _nativeExtensions[platform]!;
  yield* _filesUnder(switch (platform) {
    'macos' => 'macos/Runner',
    'windows' => 'windows/runner',
    _ => 'linux/runner',
  }, extensions);
  final packages = Directory('packages');
  if (!packages.existsSync()) return;
  for (final pkg in packages.listSync().whereType<Directory>()) {
    yield* _filesUnder('${pkg.path}/$platform', extensions);
  }
}

Map<String, String> _readAll(Iterable<String> paths) => {
  for (final p in paths) p.replaceAll(r'\', '/'): File(p).readAsStringSync(),
};

Map<String, String> _dartSources() => _readAll(
  _filesUnder('lib', const {'.dart'}).where((p) => !p.endsWith('.g.dart')),
);

Map<String, String> _nativeSources(String platform) =>
    _readAll(_nativeFiles(platform));

Set<String> _channelsIn(Map<String, String> files) {
  final names = <String>{};
  files.forEach((_, source) {
    for (final m in _channelLiteral.allMatches(stripComments(source))) {
      final name = m.group(1)!;
      if (!_notChannels.containsKey(name)) names.add(name);
    }
  });
  return names;
}

Map<String, Set<String>> _nativeRegistrations() {
  final result = <String, Set<String>>{};
  for (final platform in _platforms) {
    for (final name in _channelsIn(_nativeSources(platform))) {
      result.putIfAbsent(name, () => <String>{}).add(platform);
    }
  }
  return result;
}

void main() {
  // PAR-037: Windows and Linux do not keep the plain key any more. Modifier-only
  // keys go through watchModifier on com.whispaste.keyboard_monitor.
  test(
    'modifier_monitor allowlist reasons name the watchModifier path (PAR-037)',
    () {
      const channel = 'com.whispaste.modifier_monitor';
      for (final platform in ['windows', 'linux']) {
        final reason = _allowlist[channel]![platform]!;
        expect(
          reason,
          isNot(contains('keeps the regular hotkey')),
          reason: platform,
        );
        expect(reason, contains('watchModifier'), reason: platform);
      }
    },
  );

  // The one-time "Tap or hold" hint needs the native press length on onKeyUp.
  // A host that drops the argument would silently never show the hint.
  test('onKeyUp sends pressMs on Windows and Linux (A11Y-HINT)', () {
    const hosts = {
      'windows': 'windows/runner/keyboard_monitor_host.cpp',
      'linux': 'linux/runner/keyboard_monitor_host.cc',
    };
    for (final entry in hosts.entries) {
      final src = File(entry.value).readAsStringSync();
      expect(src, contains('"onKeyUp"'), reason: entry.key);
      expect(src, contains('"pressMs"'), reason: entry.key);
    }
  });

  test('every lib channel is registered on every platform or allowlisted', () {
    final dartChannels = _channelsIn(_dartSources());
    final native = _nativeRegistrations();
    expect(
      dartChannels,
      isNotEmpty,
      reason: 'Channel scan found nothing; the scan root or regex is wrong.',
    );

    final problems = <String>[];
    for (final channel in dartChannels.toList()..sort()) {
      final registered = native[channel] ?? const <String>{};
      final allowed = _allowlist[channel] ?? const <String, String>{};
      for (final platform in _platforms) {
        final isRegistered = registered.contains(platform);
        final isAllowed = allowed.containsKey(platform);
        if (!isRegistered && !isAllowed) {
          problems.add(
            '$channel has no $platform runner handler and no allowlist entry',
          );
        }
        if (isRegistered && isAllowed) {
          problems.add(
            '$channel is now registered on $platform; remove its allowlist entry',
          );
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('allowlist entries have reasons and reference live channels', () {
    final dartChannels = _channelsIn(_dartSources());
    final problems = <String>[];
    _allowlist.forEach((channel, perPlatform) {
      if (!dartChannels.contains(channel)) {
        problems.add('$channel is allowlisted but no longer used in lib/');
      }
      perPlatform.forEach((platform, reason) {
        if (!_platforms.contains(platform)) {
          problems.add('$channel: unknown platform "$platform"');
        }
        if (reason.trim().length < 20) {
          problems.add('$channel/$platform: reason too short to be useful');
        }
      });
    });
    _methodAllowlist.forEach((channel, perMethod) {
      perMethod.forEach((method, perPlatform) {
        perPlatform.forEach((platform, reason) {
          if (reason.trim().length < 40) {
            problems.add('$channel.$method/$platform: reason too short');
          }
        });
      });
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every Dart method call has a native handler on each platform or an '
      'allowlist entry with a reason', () {
    final dart = dartMethodsByChannel(_dartSources());
    expect(dart.methods, isNotEmpty, reason: 'Method scan found nothing.');
    final problems = methodProblems(
      dart: dart,
      nativeByPlatform: {
        for (final p in _platforms)
          p: nativeMethodsByChannel(_nativeSources(p)),
      },
      methodAllowlist: _methodAllowlist,
      channelAllowlist: _allowlist,
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  group('Linux writeClipboardText (PAR-012, GS-113, GS-128)', () {
    String linuxCase() {
      final cc = File('linux/runner/desktop_paste_host.cc').readAsStringSync();
      final start = cc.indexOf('strcmp(method, "writeClipboardText") == 0');
      expect(start, isNonNegative, reason: 'Linux writeClipboardText missing');
      final end = cc.indexOf('} else if', start + 1);
      return cc.substring(start, end == -1 ? cc.length : end);
    }

    test('writes once with the Klipper hint and reports the result', () {
      // True: Dart writes nothing more. False: Dart does the one plain write.
      final body = linuxCase();
      expect(body, contains('SetClipboardTextHidden('));
      expect(body, contains('fl_value_new_bool(hidden)'));
      expect(
        body,
        isNot(contains('gtk_clipboard_set_text')),
        reason: 'A plain native write would put the text in Klipper',
      );
      expect(
        body,
        isNot(contains('fl_value_new_bool(FALSE)')),
        reason: 'A fixed false makes Dart write plain after every paste',
      );
    });

    test('the hinted write offers the hint and all GTK text targets', () {
      final cc = File('linux/runner/clipboard_hint.cc').readAsStringSync();
      final h = File('linux/runner/clipboard_hint.h').readAsStringSync();
      expect(h, contains('"x-kde-passwordManagerHint"'));
      expect(cc, contains('gtk_target_list_add_text_targets'));
      expect(cc, contains('"secret"'));
    });
  });

  group('negative fixtures: the method check must turn red', () {
    const channel = 'com.whispaste.desktop_paste';
    const keyboard = 'com.whispaste.keyboard_monitor';

    Map<String, Map<String, Set<String>>> nativeEverywhere(
      Map<String, String> source,
    ) => {for (final p in _platforms) p: nativeMethodsByChannel(source)};

    test('a handler that only exists in a comment or a log string does not '
        'count', () {
      const native = '''
        // case "writeClipboardText":
        /* method == "writeClipboardText" */
        void log() { print("writeClipboardText not handled"); }
        const ch = "com.whispaste.desktop_paste";
      ''';
      final dart = DartCalls({
        channel: {'writeClipboardText'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems, isNotEmpty);
      expect(problems.join(), contains('desktop_paste.writeClipboardText'));
    });

    test('a real Swift case and a real C++ comparison both count', () {
      expect(
        nativeHandlersIn('switch call.method { case "a", "b": break }'),
        containsAll(['a', 'b']),
      );
      expect(
        nativeHandlersIn('if (method == "c") {} strcmp(method, "d") == 0'),
        containsAll(['c', 'd']),
      );
    });

    test('two channels in one file: a handler missing on one of them turns '
        'the check red', () {
      const native = '''
        const a = "com.whispaste.desktop_paste";
        switch call.method { case "captureTarget": break }
        const b = "com.whispaste.keyboard_monitor";
        switch call.method { case "start": break }
      ''';
      final dart = DartCalls({
        channel: {'captureTarget'},
        keyboard: {'captureTarget'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems.join(), contains('keyboard_monitor.captureTarget'));
      expect(problems.join(), isNot(contains('desktop_paste.captureTarget')));
    });

    test('a missing case turns the check red', () {
      const native = '''
        const ch = "com.whispaste.desktop_paste";
        switch call.method { case "captureTarget": break }
      ''';
      final dart = DartCalls({
        channel: {'captureTarget', 'pasteClipboard'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems.join(), contains('desktop_paste.pasteClipboard'));
    });

    test('a method attached to the wrong channel turns the check red', () {
      const dartSource = '''
        class Kbd {
          static const _kbd = MethodChannel('com.whispaste.keyboard_monitor');
          Future<void> go() => _kbd.invokeMethod<bool>('writeClipboardText');
        }
      ''';
      final dart = dartMethodsByChannel({'lib/kbd.dart': dartSource});
      expect(dart.methods[keyboard], contains('writeClipboardText'));
      expect(dart.methods[channel], isNull);

      const native = '''
        const ch = "com.whispaste.keyboard_monitor";
        switch call.method { case "start": break }
      ''';
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems.join(), contains('keyboard_monitor.writeClipboardText'));
    });

    test('code before the first channel registration is credited to no '
        'channel', () {
      const native = '''
        func preamble(call: X) { switch call.method { case "orphan": break } }
        const ch = "com.whispaste.desktop_paste";
        switch call.method { case "start": break }
      ''';
      final dart = DartCalls({
        channel: {'orphan', 'start'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems.join(), contains('desktop_paste.orphan'));
      expect(problems.join(), isNot(contains('desktop_paste.start')));
    });

    test('channels declared through constants resolve on both sides', () {
      const native = '''
        let kName = "com.whispaste.desktop_paste"
        channel = FlutterMethodChannel(name: kName, binaryMessenger: m)
        switch call.method { case "start": break }
      ''';
      final dart = DartCalls({
        channel: {'start', 'missing'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems.join(), contains('desktop_paste.missing'));
      expect(problems.join(), isNot(contains('desktop_paste.start')));

      const dartSource = '''
        const _name = 'com.whispaste.desktop_paste';
        class K { static const _ch = MethodChannel(_name); }
        void go() => K._ch.invokeMethod('start');
      ''';
      final calls = dartMethodsByChannel({'lib/k.dart': dartSource});
      expect(calls.methods[channel], contains('start'));
      expect(calls.unresolved, isEmpty);
    });

    test('a brace inside a string literal does not end a handler block', () {
      const native = '''
        const ch = "com.whispaste.desktop_paste";
        handle(call);
        func handle(_ call: X) {
          switch call.method { case "a": let s = "}"; case "b": break }
        }
      ''';
      final dart = DartCalls({
        channel: {'a', 'b'},
      }, const []);
      final problems = methodProblems(
        dart: dart,
        nativeByPlatform: nativeEverywhere({'f.swift': native}),
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('a channel imported from another file is resolved', () {
      final files = {
        'lib/a/channel.dart':
            "class Base { static const channel = MethodChannel('com.whispaste.desktop_paste'); }",
        'lib/b/user.dart':
            "import '../a/channel.dart';\nclass U extends Base { Future<void> go() => channel.invokeMethod('sendUndoShortcut'); }",
      };
      final dart = dartMethodsByChannel(files);
      expect(dart.methods[channel], contains('sendUndoShortcut'));
      expect(dart.unresolved, isEmpty);
    });
  });
}
