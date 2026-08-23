## 2024-05-24 - Missing Duplication Action in Replacements
**Learning:** The `Snippets` feature supports duplication (via the `onDuplicate` callback on its `WpRowAction`) but the similar `Replacements` feature does not. This is a recurring pattern of missing convenience actions in the UI.
**Action:** When finding a missing common action, implement it using established UI components like `WpRowAction` and existing database insert methods, just like in the Snippets page.
