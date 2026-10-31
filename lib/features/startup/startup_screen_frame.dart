/// Shared frame of the start screens that replace the app when the database
/// cannot open: one centred column of at most 520 px in one scroll area, the
/// page title, then the content. Both screens quit the same way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/tokens.dart';
import '../../services/graceful_shutdown.dart';
import '../../widgets/wp_page_header.dart';

/// The start screen layout: [title] as the page title, then [children].
class StartupScreenFrame extends StatelessWidget {
  const StartupScreenFrame({
    super.key,
    required this.title,
    required this.children,
  });

  static const double _maxWidth = 520;

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WpSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WpPageHeader(title: title),
                  const SizedBox(height: WpSpacing.md),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quits from a start screen: the engines stop first, then the window closes.
Future<void> quitFromStartupScreen(BuildContext context) async {
  await runGracefulEngineShutdown(ProviderScope.containerOf(context));
  await windowManager.destroy();
}
