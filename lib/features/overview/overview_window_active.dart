import 'package:flutter/widgets.dart';

/// For an overview block that asks the network only while it is on the page
/// and the window is active (news, weather): [onWindowActive] runs once after
/// the first frame, when the window state is known (a window that starts
/// hidden asks nothing until it is shown), and on every lifecycle change.
mixin OverviewWindowActive<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {
  /// Called with whether the window is active.
  void onWindowActive(bool active);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      onWindowActive(state == null || state == AppLifecycleState.resumed);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onWindowActive(state == AppLifecycleState.resumed);
  }
}
