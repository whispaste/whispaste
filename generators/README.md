# Generators

Screenshot generators, not tests. They live outside `test/`, so no test run
(`flutter test`, `wp-test.sh run <wt> test`, `wp-test.sh full`, CI) ever picks
them up. They share the test sandbox (`flutter_test_config.dart`) and the
helpers under `test/`.

Start one deliberately by its path:

| Generator | Command | Output |
|---|---|---|
| Store screenshots (before a store release) | `wp-test.sh run <wt> --host mac --update-goldens generators/store/store_screenshots_test.dart` | `test/screenshots/goldens/` |
| Overlay store assets | `CAPTURE_OVERLAY_ASSETS=1 wp-test.sh run <wt> --host mac generators/store/overlay_pill_asset_capture_test.dart` | `tools/appstore-screens/assets/` |
| UX screenshots (ux-reviewer) | `UX_SCREENS_DIR=<out> wp-test.sh run <wt> --host ubu generators/ux/` | `$UX_SCREENS_DIR` |

`scripts/generate-screenshots.py` wraps the store run.

When the run happens on a remote test machine, `UX_SCREENS_DIR` is a path on
that machine and the PNGs stay there; copy them back after the run.
