## 2024-08-05 - Notes in-memory filtering
**Learning:** In `lib/features/notes/data/providers.dart`, notes are filtered in-memory using `note.content.toLowerCase().contains(query)` for every keystroke. This causes excessive object allocations and overhead, especially for long notes and large note collections.
**Action:** Optimise in-memory filtering by pre-compiling search strings or avoiding repeated `toLowerCase` calls where possible. However, the query is already lowercased. So we can lowercase the content once or use regex.
