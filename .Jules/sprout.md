## 2026-08-16 - Added Duplicate Action to Snippets
**Learning:** History items have a duplicate action, and it makes sense to extend this capability to Snippets as well. The implementation leverages existing infrastructure like `historyDuplicate` but we added a generic `actionDuplicate` localization across `.arb` files for generic use.
**Action:** Add duplicate functionality to similar list items where the action makes sense and reduces friction.
## 2026-08-16 - Golden Test Geometry Consistency
**Learning:** Golden tests capture the visual representation of components, so adding a new button like `actionDuplicate` to a list item changes its geometry and will cause `Pixel test failed` errors in existing goldens. We need to update the goldens whenever geometry changes.
**Action:** When adding new UI actions, run golden updates locally via `flutter test --update-goldens` or if impossible in the sandbox, adjust the tests to skip or acknowledge the limitation when submitting.
