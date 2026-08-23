## 2024-05-24 - Missing Duplication Action in Replacements
**Learning:** The `Snippets` feature supports duplication (via the `onDuplicate` callback on its `WpRowAction`) but the similar `Replacements` feature does not. This is a recurring pattern of missing convenience actions in the UI.
**Action:** When finding a missing common action, implement it using established UI components like `WpRowAction` and existing database insert methods, just like in the Snippets page.
## 2024-05-24 - Duplicate replacements task superseded
**Learning:** PR #74 already merged this feature (and added Copy). Also #74 duplicates the *trigger phrase* (not the replacement text) to avoid two entries sharing an identical trigger, which matches the convention Snippets' duplicate action uses for its identifying field.
**Action:** When working on similar features, check for superseding PRs and be mindful of how identifying fields (like triggers or titles) are handled during duplication to prevent conflicts.
