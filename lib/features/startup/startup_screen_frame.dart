/// Shared frame of the start screens that replace the app when the database
/// cannot open: one centred column of at most 520 px in one scroll area, the
/// page title, then the content. Both screens quit the same way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../services/quit_deadline.dart';
import '../../widgets/wp_page_header.dart';

/// The start screen layout: an optional [leading] mark, [title] as the page
/// title, then [children].
class StartupScreenFrame extends StatelessWidget {
  const StartupScreenFrame({
    super.key,
    required this.title,
    required this.children,
    this.leading,
  });

  static const double _maxWidth = 520;

  final String title;
  final List<Widget> children;

  /// Shown above the title, for a screen that should first say whose screen
  /// it is (the wordmark on the data key screen). The other start screens
  /// leave it out and keep their layout.
  final Widget? leading;

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
                  if (leading case final leading?) ...[
                    leading,
                    const SizedBox(height: WpSpacing.xl),
                  ],
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

/// Quits from a start screen: the engines stop first, then the window closes,
/// under the same hard deadline as every quit path (#1609).
Future<void> quitFromStartupScreen(BuildContext context) =>
    quitFromWindow(ProviderScope.containerOf(context));
