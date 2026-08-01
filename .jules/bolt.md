## 2024-05-18 - Optimized DateTime allocation in history grouping

**Learning:** When grouping thousands of entries by date (Today, Yesterday, This Week), instantiating a new `DateTime(year, month, day)` for each item adds significant garbage collection and allocation overhead during rapid UI updates (like searching).
**Action:** Use direct property comparisons (`t.year == today.year && t.month == today.month && t.day == today.day`) for exact day matches, and use `compareTo()` with a pre-calculated date threshold (`today.subtract(const Duration(days: 6))`) for date range checks. This avoids allocating a new object per list item while keeping the logic correct.
