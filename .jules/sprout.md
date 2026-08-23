## 2025-02-23 - Added Copy Button to History Notes
**Learning:** Adding a copy button to a list item using existing helper functions (`copyToClipboardWithToast`) and existing string resources (`L10n.of(context).notesCopy`) is a highly valuable, low-risk product improvement that leverages existing infrastructure. It follows established Flutter UI patterns using `Semantics`, `Tooltip`, and `InkWell`.
**Action:** When acting as Sprout, look for missing common actions (like copy, duplicate, or delete) on existing list items or detail views, and implement them using the same patterns and helpers already present in the codebase.

## 2024-05-27 - Added Copy and Duplicate Actions to Replacements List
**Learning:** Consistently adding standard list item actions (copy, duplicate) where they are missing (e.g. Replacements page lacked actions present on Snippets page) is a safe and obvious Sprout pattern. We can reuse established components like `WpRowAction`, standard localization strings (`actionCopy`, `actionDuplicate`), and shared utilities (`copyToClipboardWithToast`).
**Action:** When working on lists, check if standard actions like Copy, Duplicate, or Delete are available on all similar lists, and port them over if they are missing using existing building blocks.
