## 2026-08-02 - Continuous Waveform Repaints
**Learning:** High-frequency animations (like the waveform in WpWaveform) inside standard widget trees trigger continuous repaints that bubble up.
**Action:** Always wrap continuous AnimatedBuilder components (especially those painting complex paths or CustomPaint) in a RepaintBoundary to isolate the redraws.
