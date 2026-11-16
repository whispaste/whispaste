import 'package:flutter/services.dart';

/// An application the user can pick for the clipboard exclusion list.
/// [id] is the platform identifier (bundle id / exe name), [name] a label.
class RunningApp {
  const RunningApp({required this.id, required this.name});

  final String id;
  final String name;
}

/// Maps the native `listRunningApps` payload to a sorted list; entries
/// without a string id are dropped, a missing name falls back to the id.
List<RunningApp> parseRunningApps(List<Map?>? raw) {
  final apps = <RunningApp>[];
  for (final entry in raw ?? const <Map?>[]) {
    final id = entry?['id'];
    if (id is! String || id.isEmpty) continue;
    final name = entry?['name'];
    apps.add(RunningApp(id: id, name: name is String ? name : id));
  }
  apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return apps;
}

/// Asks the native clipboard host for the running desktop apps. Empty where
/// the platform has no such method (Linux, [MissingPluginException]). A
/// native failure ([PlatformException]) propagates so the settings can show
/// an error state instead of an empty list.
Future<List<RunningApp>> listRunningApps({
  MethodChannel channel = const MethodChannel(
    'com.whispaste.clipboard_history',
  ),
}) async {
  try {
    return parseRunningApps(
      await channel.invokeListMethod<Map>('listRunningApps'),
    );
  } on MissingPluginException {
    return const [];
  }
}
