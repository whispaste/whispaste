import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/weather.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/weather/weather_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/external_link.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_control_row.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_text_field.dart';
import '../../widgets/wp_text_link.dart';
import 'overview_window_active.dart';

/// "Wetter" (#1569): the weather of one chosen place, from MET Norway. Off by
/// default; switched on under "Übersicht anpassen". No place, no request.
/// The forecast is asked for only while this card is on the page and the
/// window is active, and only when the stored one is due (Expires, at most
/// once an hour; after a failure every 30 minutes). Offline it shows the
/// stored forecast or a calm line.
class OverviewWeatherCard extends ConsumerStatefulWidget {
  const OverviewWeatherCard({super.key});

  @override
  ConsumerState<OverviewWeatherCard> createState() =>
      _OverviewWeatherCardState();
}

class _OverviewWeatherCardState extends ConsumerState<OverviewWeatherCard>
    with WidgetsBindingObserver, OverviewWindowActive {
  bool _active = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void onWindowActive(bool active) => _setActive(active);

  void _setActive(bool active) {
    _active = active;
    if (!active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    unawaited(_refresh());
  }

  /// Asks when due, then sets the timer to the next due time.
  Future<void> _refresh() async {
    await ref.read(weatherProvider.notifier).refreshIfDue();
    if (mounted) _schedule(ref.read(weatherProvider).nextAttempt);
  }

  /// One timer to the next due time, only while the window is active. It
  /// dies with the card, so nothing runs once the overview is left.
  void _schedule(DateTime? next) {
    _timer?.cancel();
    _timer = null;
    if (!_active || next == null) return;
    var wait = next.difference(clock.now().toUtc());
    if (wait.isNegative) wait = Duration.zero;
    _timer = Timer(wait + const Duration(seconds: 1), () {
      if (mounted && _active) unawaited(_refresh());
    });
  }

  Future<void> _choosePlace() async {
    final current = ref.read(weatherProvider).place;
    final choice = await showWeatherPlaceDialog(
      context: context,
      hasPlace: current != null,
    );
    if (!mounted || choice == null) return;
    final notifier = ref.read(weatherProvider.notifier);
    switch (choice) {
      case WeatherPlaceChosen(:final place):
        await notifier.setPlace(place);
      case WeatherPlaceRemoved():
        await notifier.clearPlace();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    ref.listen(
      weatherProvider.select((v) => v.nextAttempt),
      (_, next) => _schedule(next),
    );
    final view = ref.watch(weatherProvider);
    final place = view.place;
    return WpCard(
      key: const ValueKey('overview-weather'),
      title: l10n.overviewWeatherTitle,
      titleTestId: 'overview-weather-title',
      subtitle: place?.name,
      trailing: place == null
          ? null
          : WpTextLink(
              testID: 'overview-weather-change',
              label: l10n.overviewWeatherChangePlace,
              kind: WpLinkKind.action,
              onPressed: () => unawaited(_choosePlace()),
            ),
      child: !view.loaded
          ? Text('…', style: WpTextStyles.rowNote)
          : place == null
          ? _NoPlace(onChoose: () => unawaited(_choosePlace()))
          : _Forecast(view: view),
    );
  }
}

class _NoPlace extends StatelessWidget {
  const _NoPlace({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: const ValueKey('overview-weather-no-place'),
          l10n.overviewWeatherNoPlace,
          style: WpTextStyles.rowNote,
        ),
        const SizedBox(height: WpSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: WpButton(
            testId: 'overview-weather-choose',
            label: l10n.overviewWeatherChoosePlace,
            variant: WpButtonVariant.secondary,
            onPressed: onChoose,
          ),
        ),
      ],
    );
  }
}

class _Forecast extends StatelessWidget {
  const _Forecast({required this.view});

  final WeatherView view;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final now = clock.now();
    final hours = view.cache?.hours ?? const <WeatherHour>[];
    final hour = weatherHourAt(hours, now);
    final range = weatherRange(hours, now);
    final cache = view.cache;

    final children = <Widget>[];
    if (hour != null && hour.temperatureC != null) {
      final temp = l10n.overviewWeatherDegrees(hour.temperatureC!.round());
      final condition = weatherConditionOf(hour.symbol);
      final conditionText = condition == null
          ? null
          : _conditionLabel(l10n, condition);
      children.add(
        Semantics(
          key: const ValueKey('overview-weather-now'),
          container: true,
          label: [temp, ?conditionText].join(', '),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(
                  _conditionIcon(condition, weatherSymbolIsNight(hour.symbol)),
                  size: WpIconSize.xl,
                  color: WpColors.textSecondary,
                ),
                const SizedBox(width: WpSpacing.md),
                Text(temp, style: WpTextStyles.figure),
                const SizedBox(width: WpSpacing.md),
                if (conditionText != null)
                  Expanded(
                    child: Text(conditionText, style: WpTextStyles.rowTitle),
                  ),
              ],
            ),
          ),
        ),
      );
      if (range != null) {
        children.addAll([
          const SizedBox(height: WpSpacing.xs),
          Text(
            key: const ValueKey('overview-weather-range'),
            l10n.overviewWeatherRange(
              l10n.overviewWeatherDegrees(range.low.round()),
              l10n.overviewWeatherDegrees(range.high.round()),
            ),
            style: WpTextStyles.rowNote,
          ),
        ]);
      }
    } else if (cache == null && !view.lastFailed) {
      children.add(Text('…', style: WpTextStyles.rowNote));
    } else {
      children.add(
        Text(
          key: const ValueKey('overview-weather-unavailable'),
          l10n.overviewWeatherUnavailable,
          style: WpTextStyles.rowNote,
        ),
      );
    }

    if (cache != null) {
      children.addAll([
        const SizedBox(height: WpSpacing.xs),
        Text(
          key: const ValueKey('overview-weather-updated'),
          l10n.overviewWeatherUpdated(
            DateFormat.Hm(lang).format(cache.fetchedAt.toLocal()),
          ),
          style: WpTextStyles.rowNote,
        ),
      ]);
    }

    children.addAll([
      const SizedBox(height: WpSpacing.sm),
      const WpRowDivider(),
      const SizedBox(height: WpSpacing.xs),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: WpTextLink(
          testID: 'overview-weather-attribution',
          label: l10n.overviewWeatherAttribution,
          kind: WpLinkKind.web,
          onPressed: () => unawaited(openExternalUrl(context, kMetLicenceUrl)),
        ),
      ),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

String _conditionLabel(L10n l10n, WeatherCondition c) => switch (c) {
  WeatherCondition.clear => l10n.overviewWeatherClear,
  WeatherCondition.fair => l10n.overviewWeatherFair,
  WeatherCondition.partlyCloudy => l10n.overviewWeatherPartlyCloudy,
  WeatherCondition.cloudy => l10n.overviewWeatherCloudy,
  WeatherCondition.fog => l10n.overviewWeatherFog,
  WeatherCondition.rain => l10n.overviewWeatherRain,
  WeatherCondition.sleet => l10n.overviewWeatherSleet,
  WeatherCondition.snow => l10n.overviewWeatherSnow,
  WeatherCondition.thunder => l10n.overviewWeatherThunder,
};

IconData _conditionIcon(WeatherCondition? c, bool night) => switch (c) {
  WeatherCondition.clear => night ? LucideIcons.moon : LucideIcons.sun,
  WeatherCondition.fair || WeatherCondition.partlyCloudy =>
    night ? LucideIcons.cloudMoon : LucideIcons.cloudSun,
  WeatherCondition.cloudy || null => LucideIcons.cloud,
  WeatherCondition.fog => LucideIcons.cloudFog,
  WeatherCondition.rain => LucideIcons.cloudRain,
  WeatherCondition.sleet => LucideIcons.cloudHail,
  WeatherCondition.snow => LucideIcons.cloudSnow,
  WeatherCondition.thunder => LucideIcons.cloudLightning,
};

// ---------------------------------------------------------------------------
// Place dialog
// ---------------------------------------------------------------------------

/// What the place dialog returns.
sealed class WeatherPlaceChoice {
  const WeatherPlaceChoice();
}

final class WeatherPlaceChosen extends WeatherPlaceChoice {
  const WeatherPlaceChosen(this.place);
  final WeatherPlace place;
}

final class WeatherPlaceRemoved extends WeatherPlaceChoice {
  const WeatherPlaceRemoved();
}

/// Asks for the place: a search field (sent only on "Suchen" or Enter, never
/// while typing), the hits, and the notice which data goes where. Returns
/// null when cancelled.
Future<WeatherPlaceChoice?> showWeatherPlaceDialog({
  required BuildContext context,
  required bool hasPlace,
}) => showWpFormDialog<WeatherPlaceChoice>(
  context: context,
  builder: (ctx, animation) =>
      _WeatherPlaceDialog(animation: animation, hasPlace: hasPlace),
);

class _WeatherPlaceDialog extends ConsumerStatefulWidget {
  const _WeatherPlaceDialog({required this.animation, required this.hasPlace});

  final Animation<double> animation;
  final bool hasPlace;

  @override
  ConsumerState<_WeatherPlaceDialog> createState() =>
      _WeatherPlaceDialogState();
}

enum _SearchState { idle, searching, done, failed }

class _WeatherPlaceDialogState extends ConsumerState<_WeatherPlaceDialog> {
  final TextEditingController _query = TextEditingController();
  _SearchState _state = _SearchState.idle;
  List<GeocodeResult> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_state == _SearchState.searching) return;
    if (geocodeQuery(_query.text) == null) return;
    final lang = Localizations.localeOf(context).languageCode;
    setState(() => _state = _SearchState.searching);
    try {
      final results = await ref
          .read(placeSearchProvider)
          .search(_query.text, lang);
      if (!mounted) return;
      setState(() {
        _results = results;
        _state = _SearchState.done;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _state = _SearchState.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final searching = _state == _SearchState.searching;
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.overviewWeatherDialogTitle,
      subtitle: l10n.overviewWeatherDialogPrivacy,
      fields: [
        WpControlRow(
          children: [
            Expanded(
              child: WpTextField(
                key: const ValueKey('overview-weather-query'),
                controller: _query,
                variant: WpTextFieldVariant.form,
                autofocus: true,
                hintText: l10n.overviewWeatherSearchHint,
                semanticsLabel: l10n.overviewWeatherSearchHint,
                onSubmitted: (_) => unawaited(_search()),
              ),
            ),
            WpButton(
              testId: 'overview-weather-search',
              label: l10n.overviewWeatherSearch,
              variant: WpButtonVariant.secondary,
              isLoading: searching,
              onPressed: searching ? null : () => unawaited(_search()),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.md),
        if (_state == _SearchState.failed)
          Semantics(
            liveRegion: true,
            child: Text(
              key: const ValueKey('overview-weather-search-failed'),
              l10n.overviewWeatherSearchFailed,
              style: WpTextStyles.rowNote,
            ),
          )
        else if (_state == _SearchState.done && _results.isEmpty)
          Semantics(
            liveRegion: true,
            child: Text(
              key: const ValueKey('overview-weather-no-results'),
              l10n.overviewWeatherNoResults,
              style: WpTextStyles.rowNote,
            ),
          )
        else if (_results.isNotEmpty) ...[
          for (final (i, r) in _results.indexed) ...[
            if (i > 0) const WpRowDivider(),
            _ResultRow(
              index: i,
              result: r,
              onUse: () =>
                  Navigator.of(context).pop(WeatherPlaceChosen(r.toPlace())),
            ),
          ],
          const SizedBox(height: WpSpacing.sm),
          // ODbL: the credit links to the OpenStreetMap copyright page.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WpTextLink(
              testID: 'overview-weather-search-attribution',
              label: l10n.overviewWeatherSearchAttribution,
              kind: WpLinkKind.web,
              onPressed: () =>
                  unawaited(openExternalUrl(context, kOsmCopyrightUrl)),
            ),
          ),
        ],
      ],
      actions: [
        if (widget.hasPlace)
          WpDialogAction<Object?>(
            label: l10n.overviewWeatherRemovePlace,
            testId: 'overview-weather-remove',
            role: WpDialogActionRole.alternative,
            onPressed: () =>
                Navigator.of(context).pop(const WeatherPlaceRemoved()),
          ),
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'overview-weather-cancel',
          role: WpDialogActionRole.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.index,
    required this.result,
    required this.onUse,
  });

  final int index;
  final GeocodeResult result;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.name, style: WpTextStyles.rowTitle),
                if (result.label != result.name)
                  Text(
                    result.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WpTextStyles.rowNote,
                  ),
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.md),
          WpButton(
            testId: 'overview-weather-use-$index',
            label: l10n.overviewWeatherUse,
            semanticsLabel: '${l10n.overviewWeatherUse}: ${result.label}',
            variant: WpButtonVariant.secondary,
            onPressed: onUse,
          ),
        ],
      ),
    );
  }
}
