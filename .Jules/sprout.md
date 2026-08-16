## 2026-08-16 - Added Duplicate Action to Snippets
**Learning:** History items have a duplicate action, and it makes sense to extend this capability to Snippets as well. The implementation leverages existing infrastructure like `historyDuplicate` but we added a generic `actionDuplicate` localization across `.arb` files for generic use.
**Action:** Add duplicate functionality to similar list items where the action makes sense and reduces friction.
