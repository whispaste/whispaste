import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Largest share of pixels (0.1 %) a golden may differ by and still pass.
///
/// Baselines are generated on the maintainer's Mac; CI renders them on a
/// GitHub-hosted macOS runner. The two differ only in anti-aliasing: the
/// first hosted run (36710725313) failed 24 exact-match goldens by
/// 0.00-0.02 % of pixels each, with no size or layout change. 0.1 % leaves
/// headroom for that while still catching any visible UI change (a moved or
/// recoloured widget changes far more pixels).
///
/// Note the unit: [ComparisonResult.diffPercent] is a fraction (0-1), so
/// 0.1 % is 0.001 here.
const double kGoldenPixelTolerance = 0.001;

/// Whether a golden comparison [result] passes under [kGoldenPixelTolerance].
bool withinGoldenTolerance(ComparisonResult result) =>
    result.passed || result.diffPercent <= kGoldenPixelTolerance;

/// [LocalFileComparator] that accepts differences up to
/// [kGoldenPixelTolerance]. `--update-goldens` still writes exact baselines.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    try {
      if (withinGoldenTolerance(result)) return true;
      throw FlutterError(await generateFailureOutput(result, golden, basedir));
    } finally {
      result.dispose();
    }
  }
}
