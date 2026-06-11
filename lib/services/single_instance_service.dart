import 'dart:io';

import '../core/logging/app_logger.dart';

/// Ensures only one instance of WhisPaste runs at a time.
///
/// Uses a local TCP server on a fixed port. If binding succeeds, this is the
/// primary instance. If binding fails (port in use), another instance is
/// already running — we signal it to focus and then exit.
class SingleInstanceService {
  static const int _port = 47293; // Fixed port for instance detection
  static const String _focusCommand = 'WHISPASTE_FOCUS';
  static final _log = AppLogger('SingleInstance');

  static ServerSocket? _server;

  /// Callback invoked when a second instance requests focus.
  static void Function()? onSecondInstanceLaunched;

  /// Attempt to claim the single-instance lock.
  /// Returns `true` if this is the primary instance.
  /// Returns `false` if another instance is already running (and was signalled).
  static Future<bool> ensureSingleInstance() async {
    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: false,
      );
      _server!.listen(_handleConnection);
      _log.info('Single instance lock acquired on port $_port');
      return true;
    } on SocketException {
      // Port is already bound → another instance is running.
      _log.info('Another instance detected, sending focus signal');
      await _signalExistingInstance();
      return false;
    }
  }

  /// Handle incoming connections from secondary instances.
  static void _handleConnection(Socket socket) {
    socket.listen((data) {
      final message = String.fromCharCodes(data).trim();
      if (message == _focusCommand) {
        _log.info('Received focus signal from second instance');
        onSecondInstanceLaunched?.call();
      }
      socket.close();
    }, onError: (_) => socket.destroy());
  }

  /// Signal the already-running instance to focus its window.
  static Future<void> _signalExistingInstance() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.write(_focusCommand);
      await socket.flush();
      await socket.close();
    } catch (e) {
      _log.warning('Failed to signal existing instance: $e');
    }
  }
}
