## 2024-07-30 - Dart String Splitting Performance
**Learning:** Using `text.trim().split(RegExp(r'\s+')).length` for word counting is a significant performance bottleneck in Dart, especially inside Flutter list rendering (like `ListView.builder`), due to heavy object allocation (creating RegExp objects and String arrays).
**Action:** Always prefer manual O(n) loops to count characters (like word boundaries) over regex-based string splitting when calculating simple metrics on long text within UI rendering loops.
