/// The user's first name as the operating system knows it, for the greeting
/// on the onboarding screen "Über dich".
///
/// macOS and Linux read the GECOS field of the current user with
/// `getpwuid(getuid())` in process (the Mac App Store sandbox blocks child
/// processes such as `id -F`); Windows asks `GetUserNameExW(NameDisplay)` and,
/// for local accounts, `NetUserGetInfo` (level 10, full name).
/// Nothing leaves the device, nothing prompts, and any failure is `null`.
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Account names that never are a person's name.
const _genericNames = {
  'admin',
  'administrator',
  'administrador',
  'administrateur',
  'amministratore',
  'benutzer',
  'default',
  'gast',
  'guest',
  'nutzer',
  'owner',
  'root',
  'user',
  'usuario',
  'utilisateur',
};

/// First name from a raw full name, or `null` when it is not a usable name.
///
/// [rawFullName] is the GECOS field (macOS/Linux) or the Windows display
/// name; [loginName] is `$USER` / `%USERNAME%`. A GECOS value keeps only the
/// part before the first comma (room, phones follow). A Windows display name
/// in directory form "Last, First" yields the part after the comma.
String? extractFirstName(
  String? rawFullName, {
  String? loginName,
  bool windowsDisplayName = false,
}) {
  if (rawFullName == null) return null;
  var full = rawFullName.trim();
  final comma = full.indexOf(',');
  if (comma >= 0) {
    full = windowsDisplayName
        ? full.substring(comma + 1).trim()
        : full.substring(0, comma).trim();
  }
  if (full.isEmpty) return null;
  // Exact match only: "Silvio" for login "silvio" is a chosen name.
  if (full == loginName?.trim()) return null;
  // A single lowercase word looks like a login name, not a chosen name.
  if (!full.contains(RegExp(r'\s')) && full == full.toLowerCase()) return null;
  final tokens = full.split(RegExp(r'\s+'));
  // "System Administrator", "Gast Konto": an account label, not a person.
  if (tokens.any((t) => _genericNames.contains(t.toLowerCase()))) return null;
  // Skip leading titles such as "Dr." when a name follows.
  var first = tokens.first;
  for (final token in tokens) {
    if (!token.endsWith('.')) {
      first = token;
      break;
    }
  }
  return first;
}

/// Reads the first name of the signed-in user, within [timeout].
Future<String?> readSystemFirstName({
  Duration timeout = const Duration(seconds: 1),
}) async {
  try {
    final windows = Platform.isWindows;
    if (!windows && !Platform.isMacOS && !Platform.isLinux) return null;
    final login = Platform.environment[windows ? 'USERNAME' : 'USER'];
    final raw = await Isolate.run(
      windows ? () => _windowsFullName(login) : _posixGecos,
    ).timeout(timeout);
    return extractFirstName(raw, loginName: login, windowsDisplayName: windows);
  } on Object {
    return null;
  }
}

/// The first name for the onboarding. Tests override it.
final systemFirstNameProvider = FutureProvider<String?>(
  (ref) => readSystemFirstName(),
);

typedef _GetuidC = ffi.Uint32 Function();
typedef _GetuidDart = int Function();
typedef _GetpwuidC = ffi.Pointer<ffi.IntPtr> Function(ffi.Uint32);
typedef _GetpwuidDart = ffi.Pointer<ffi.IntPtr> Function(int);

/// Pointer-sized slot of `pw_gecos` in `struct passwd` (64 bit): Darwin has
/// `pw_change` and `pw_class` before it, glibc follows `pw_gid` directly.
int get _gecosSlot => Platform.isMacOS ? 5 : 3;

String? _posixGecos() {
  final libc = ffi.DynamicLibrary.process();
  final getuid = libc.lookupFunction<_GetuidC, _GetuidDart>('getuid');
  final getpwuid = libc.lookupFunction<_GetpwuidC, _GetpwuidDart>('getpwuid');
  final entry = getpwuid(getuid());
  if (entry == ffi.nullptr) return null;
  final gecos = ffi.Pointer<Utf8>.fromAddress(entry[_gecosSlot]);
  if (gecos == ffi.nullptr) return null;
  return gecos.toDartString();
}

typedef _GetUserNameExC =
    ffi.Uint8 Function(ffi.Int32, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>);
typedef _GetUserNameExDart =
    int Function(int, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Uint32>);

typedef _NetUserGetInfoC =
    ffi.Uint32 Function(
      ffi.Pointer<Utf16>,
      ffi.Pointer<Utf16>,
      ffi.Uint32,
      ffi.Pointer<ffi.Pointer<ffi.IntPtr>>,
    );
typedef _NetUserGetInfoDart =
    int Function(
      ffi.Pointer<Utf16>,
      ffi.Pointer<Utf16>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.IntPtr>>,
    );
typedef _NetApiBufferFreeC = ffi.Uint32 Function(ffi.Pointer<ffi.IntPtr>);
typedef _NetApiBufferFreeDart = int Function(ffi.Pointer<ffi.IntPtr>);

/// `EXTENDED_NAME_FORMAT.NameDisplay`.
const _nameDisplay = 3;

/// Pointer slot of `usri10_full_name` in `USER_INFO_10`.
const _fullNameSlot = 3;

/// The display name of a domain or Microsoft account, else the full name of
/// the local account: `NameDisplay` fails for most local accounts, which are
/// the common case on home PCs.
String? _windowsFullName(String? login) {
  final display = _windowsDisplayName();
  if (display != null && display.trim().isNotEmpty) return display;
  return login == null || login.isEmpty ? null : _netUserFullName(login);
}

String? _netUserFullName(String login) {
  final netapi32 = ffi.DynamicLibrary.open('netapi32.dll');
  final getInfo = netapi32
      .lookupFunction<_NetUserGetInfoC, _NetUserGetInfoDart>('NetUserGetInfo');
  final free = netapi32
      .lookupFunction<_NetApiBufferFreeC, _NetApiBufferFreeDart>(
        'NetApiBufferFree',
      );
  return using((arena) {
    final out = arena<ffi.Pointer<ffi.IntPtr>>();
    final status = getInfo(
      ffi.nullptr,
      login.toNativeUtf16(allocator: arena),
      10,
      out,
    );
    if (status != 0 || out.value == ffi.nullptr) return null;
    try {
      final name = ffi.Pointer<Utf16>.fromAddress(out.value[_fullNameSlot]);
      return name == ffi.nullptr ? null : name.toDartString();
    } finally {
      free(out.value);
    }
  });
}

String? _windowsDisplayName() {
  final secur32 = ffi.DynamicLibrary.open('secur32.dll');
  final getUserNameEx = secur32
      .lookupFunction<_GetUserNameExC, _GetUserNameExDart>('GetUserNameExW');
  return using((arena) {
    final size = arena<ffi.Uint32>()..value = 256;
    final buffer = arena<ffi.Uint16>(size.value).cast<Utf16>();
    if (getUserNameEx(_nameDisplay, buffer, size) == 0) return null;
    return buffer.toDartString(length: size.value);
  });
}
