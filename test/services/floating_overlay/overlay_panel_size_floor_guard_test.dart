// Overlay panel size floor guard (OVERLAY-BACKING-STORE).
//
// On macOS the floating overlay's render engine draws into an NSPanel that is
// ordered out between recordings. AppKit may let such a hidden panel collapse
// to 0x0 (observed live 2026-10-26: `resizePanelToContent ... panel.isVisible=false,
// frame=(0,0,0,0)`). The embedder then cannot create a backing store for the
// render surface, and every frame logs `Could not create the embedder backing
// store`. That logging ran at frame rate for days in one reported session and
// wrote 108 GB of stderr.
//
// The fix gives the panel a minimum frame size that AppKit cannot undercut:
// `FloatingOverlayPanel` clamps `setFrame` / `setContentSize` to
// `minimumFrameSize`, and the host sets that floor to the current size class
// before the panel is attached to the render engine.
//
// Windows and Linux hosts keep an explicit non-zero size while hidden (a hidden
// HWND / GTK window keeps its size), so they have no equivalent collapse. This
// test checks that they still set a size explicitly, so the parity claim is
// guarded too.
//
// Static check: it proves the floor is wired, not that AppKit never collapses
// the window. The live check is the stderr/CPU measurement in the ticket.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads a native source file. Plain I/O on purpose: `expect` is not allowed
/// outside a test body, and a missing file already fails the test loudly.
String _read(String path) => File(path).readAsStringSync();

void main() {
  final window = _read('macos/Runner/FloatingOverlayWindow.swift');
  final host = _read('macos/Runner/FloatingOverlayHost.swift');

  group('macOS overlay panel size floor', () {
    test('the panel exposes a minimum frame size', () {
      expect(
        window,
        contains('var minimumFrameSize'),
        reason: 'the floor must be a property the host can set per size class',
      );
    });

    test('setFrame cannot shrink the panel below the floor', () {
      expect(
        window,
        contains(
          'override func setFrame(_ frameRect: NSRect, display flag: Bool)',
        ),
        reason:
            'AppKit collapses a hidden panel through setFrame; the override is '
            'the only place a 0x0 frame can be stopped',
      );
      expect(
        window,
        contains('super.setFrame(Self.clamped('),
        reason: 'the override must pass the clamped rect to AppKit',
      );
    });

    test('setContentSize cannot shrink the panel below the floor', () {
      expect(
        window,
        contains('override func setContentSize(_ size: NSSize)'),
        reason: 'the host resizes through setContentSize',
      );
    });

    test('the host sets the floor on every attach and every resize', () {
      // bootRenderEngine runs for panel creation, for stuck-panel rebuilds and
      // for engine re-boots, so one assignment there covers all attaches.
      // resizePanelToContent covers a size-class switch on a live panel.
      final assignments = RegExp(
        r'\.minimumFrameSize = contentSize\(\)',
      ).allMatches(host).length;
      expect(
        assignments,
        greaterThanOrEqualTo(2),
        reason:
            'bootRenderEngine (every attach) and resizePanelToContent (size '
            'switch) must each set the floor to the current size class',
      );
    });

    test('the floor is set before the view controller is attached', () {
      final attach = host.indexOf('p.contentViewController = vc');
      final floor = host.indexOf('minimumFrameSize = contentSize()', 0);
      expect(attach, isNot(-1), reason: 'bootRenderEngine attaches the view');
      expect(
        floor,
        isNot(-1),
        reason: 'the host must set the floor from contentSize()',
      );
      expect(
        floor < attach,
        isTrue,
        reason:
            'the floor must exist before AppKit adopts the render view\'s size; '
            'a view controller without a size is what collapses the window',
      );
    });
  });

  group('Windows and Linux overlay shells keep an explicit size', () {
    test('Windows sizes the hidden shell explicitly', () {
      final winHost = _read('windows/runner/floating_overlay_host.cpp');
      final winWindow = _read('windows/runner/floating_overlay_window.cpp');
      expect(
        winHost,
        contains('window_->SetSize('),
        reason: 'the Windows host sets the shell size on each size class',
      );
      expect(
        winWindow,
        contains('SetWindowPos(hwnd_, nullptr, 0, 0, phys_w, phys_h'),
        reason: 'the shell size is an explicit window position, not adopted',
      );
    });

    test('Linux sizes the hidden shell explicitly', () {
      final linuxWindow = _read('linux/runner/floating_overlay_window.cc');
      expect(
        linuxWindow,
        contains('gtk_widget_set_size_request(window_, w, h);'),
        reason: 'the GTK shell keeps an explicit size request while hidden',
      );
    });
  });
}
