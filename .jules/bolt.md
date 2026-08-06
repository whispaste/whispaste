## 2024-05-24 - Case-Insensitive String Filtering Allocation
**Learning:** Dart's String.toLowerCase() allocates a new string. Doing this multiple times per item in an Iterable.where() tight loop causes massive GC pressure, especially when users type quickly in a search bar over a large dataset.
**Action:** Always prefer precompiled RegExp(pattern, caseSensitive: false) for case-insensitive filtering in list processing, initializing it once outside the loop to avoid O(N) allocations.
