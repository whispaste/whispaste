import 'package:flutter/widgets.dart';

/// The app navigator. Its context sits under the app's toast overlay, so
/// notices raised from a menu command or a tray choice are visible. Kept in
/// core, without imports from the widget tree, so services can reach it
/// without an import cycle.
final appNavigatorKey = GlobalKey<NavigatorState>();
