import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the record plugin's device listing with an empty list.
///
/// The plugin never answers inside the widget test binding, so the listing
/// timeout (RE2-09) would leave a pending timer behind and fail the test. Call
/// once at the start of `main()` in widget tests that build the settings page.
void stubRecordDeviceListing() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => call.method == 'listInputDevices' ? <Object?>[] : null,
      );
}
