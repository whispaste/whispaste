// Generators run with the same app-data sandbox as the tests: without it,
// code that sweeps or erases app data would act on the real app data
// directory of whoever renders the screenshots.
export '../test/flutter_test_config.dart';
