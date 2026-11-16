/// V1 Wayland: which keyboard path a Linux paste takes (uinput or the
/// RemoteDesktop portal) and how it falls back when one lacks access.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_portal_input.dart';

class _MemoryTokenStore implements PortalRestoreTokenStore {
  _MemoryTokenStore([this.token]);
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

class _NoFocus implements FocusedTargetSource {
  @override
  String get name => 'none';

  @override
  Future<FocusedTarget?> focusedTarget() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.whispaste.desktop_paste');
  late List<MethodCall> calls;
  late bool uinputOk;
  late bool portalOk;
  late String connectStatus;

  setUp(() {
    calls = [];
    uinputOk = true;
    portalOk = true;
    connectStatus = 'connected';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments is Map ? call.arguments as Map : {};
          final portal = args['via'] == 'portal';
          return switch (call.method) {
            'portalInputAvailable' => true,
            'portalInputConnect' => {
              'status': connectStatus,
              'restoreToken': connectStatus == 'connected' ? 'tok-2' : null,
            },
            'portalInputDisconnect' => null,
            'checkCapability' => {
              'status': uinputOk ? 'ready' : 'permission_missing',
            },
            'pasteClipboard' || 'copySelection' =>
              (portal ? portalOk : uinputOk)
                  ? {'status': 'success'}
                  : {'status': 'permission_missing'},
            _ => null,
          };
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  LinuxDesktopPasteController controller({
    bool preferPortal = false,
    _MemoryTokenStore? store,
  }) => LinuxDesktopPasteController(
    waylandFocus: _NoFocus(),
    preferPortal: preferPortal,
    portal: LinuxPortalInput(tokenStore: store ?? _MemoryTokenStore()),
  );

  /// The keyboard paths the paste calls took, in order, with their delays.
  List<String> routes() => [
    for (final c in calls.where(
      (c) => c.method == 'pasteClipboard' || c.method == 'copySelection',
    ))
      '${(c.arguments as Map)['via'] ?? 'uinput'}'
          '@${(c.arguments as Map)['delayMs']}',
  ];

  const delay = Duration(milliseconds: 40);

  test('without a portal session only uinput is used', () async {
    uinputOk = false;
    final c = controller();
    final result = await c.pasteClipboard(delay: delay);
    expect(result.status, NativePasteStatus.permissionMissing);
    expect(routes(), ['uinput@40']);
  });

  test('uinput without access falls back to the portal at once', () async {
    uinputOk = false;
    final c = controller();
    expect((await c.connectPortalInput()).isConnected, isTrue);

    final result = await c.copySelection(delay: delay);

    expect(result.isSuccess, isTrue);
    expect(routes(), ['uinput@40', 'portal@0']);
  });

  test('a working uinput keeps the portal out of the way', () async {
    final c = controller();
    await c.connectPortalInput();
    await c.pasteClipboard(delay: delay);
    expect(routes(), ['uinput@40']);
  });

  test(
    'inside Flatpak the portal goes first, uinput is the fallback',
    () async {
      final c = controller(preferPortal: true);
      await c.connectPortalInput();
      await c.pasteClipboard(delay: delay);
      portalOk = false;
      await c.pasteClipboard(delay: delay);

      expect(routes(), ['portal@40', 'portal@40', 'uinput@0']);
      expect(c.portalInputConnected, isFalse, reason: 'session gone');
      await c.pasteClipboard(delay: delay);
      expect(routes().last, 'uinput@40');
    },
  );

  test('a cancelled consent dialog leaves uinput alone', () async {
    connectStatus = 'cancelled';
    final c = controller(preferPortal: true);
    expect((await c.connectPortalInput()).isConnected, isFalse);
    await c.pasteClipboard(delay: delay);
    expect(routes(), ['uinput@40']);
  });

  test('capability is ready while the portal stands in for uinput', () async {
    uinputOk = false;
    final c = controller();
    expect(
      (await c.checkCapability()).status,
      NativeCapabilityStatus.permissionMissing,
    );
    await c.connectPortalInput();
    final cap = await c.checkCapability();
    expect(cap.status, NativeCapabilityStatus.ready);
    expect(cap.detail, 'portal');
  });

  group('resume and revoke', () {
    test('resumes only after an earlier consent', () async {
      await controller().resumePortalInput();
      expect(calls.where((c) => c.method == 'portalInputConnect'), isEmpty);

      final store = _MemoryTokenStore('tok-1');
      final c = controller(store: store);
      await c.resumePortalInput();
      final connect = calls.singleWhere(
        (c) => c.method == 'portalInputConnect',
      );
      expect((connect.arguments as Map)['restoreToken'], 'tok-1');
      expect(c.portalInputConnected, isTrue);
      expect(store.token, 'tok-2', reason: 'the new token replaces the old');
    });

    test('revoke closes the session and forgets the consent', () async {
      final store = _MemoryTokenStore('tok-1');
      final c = controller(store: store);
      await c.resumePortalInput();
      await c.revokePortalInput();
      expect(c.portalInputConnected, isFalse);
      expect(store.token, isNull);
      expect(calls.last.method, 'portalInputDisconnect');
    });
  });
}
