import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/features/help/support_value.dart';

AnalyticsData _data({required int words, required int savedMinutes}) =>
    AnalyticsData(
      totalRecordings: 1,
      totalDurationMinutes: 1,
      totalWords: words,
      timeSavedMinutes: savedMinutes,
      modelUsage: const [],
      durationBuckets: const [0, 0, 0, 0, 0],
      localSavingsUsd: 0,
      cloudCostUsd: 0,
    );

void main() {
  test('below the word threshold there is no value line', () {
    expect(
      supportValueFrom(
        _data(words: kSupportValueMinWords - 1, savedMinutes: 30),
      ),
      isNull,
    );
  });

  test('without saved typing time there is no value line', () {
    expect(
      supportValueFrom(_data(words: kSupportValueMinWords, savedMinutes: 0)),
      isNull,
    );
  });

  test('from the threshold on the line carries the all-time figures', () {
    expect(supportValueFrom(_data(words: 12345, savedMinutes: 246)), (
      words: 12345,
      savedMinutes: 246,
    ));
  });

  test('a fresh install shows no value line', () {
    expect(supportValueFrom(AnalyticsData.empty), isNull);
  });
}
