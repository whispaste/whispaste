/// Scripted elapsed time for APIs that accept a stopwatch. Never reads a clock.
class FixedStopwatch implements Stopwatch {
  FixedStopwatch(this.elapsed);

  @override
  final Duration elapsed;

  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;

  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;

  @override
  int get elapsedTicks => elapsedMicroseconds;

  @override
  int get frequency => Duration.microsecondsPerSecond;

  @override
  bool get isRunning => false;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void reset() {}
}
