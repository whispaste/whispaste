/// The "Systemkarte" of the Übersicht: the pure rules for CPU load, memory and
/// free disk space. Everything here is a function over plain numbers and
/// strings, so the rules are tested without the OS. The readings themselves
/// live in `services/system_usage_service.dart`.
library;

/// Cumulative CPU time of the whole machine, in clock ticks of one kind.
/// [busy] is every tick that was not idle (including I/O wait counts as idle).
class CpuTicks {
  const CpuTicks({required this.busy, required this.total});

  final int busy;
  final int total;
}

/// Parses the first line of Linux `/proc/stat` (`cpu user nice system idle
/// iowait irq softirq steal …`). `guest` and `guest_nice` are left out: the
/// kernel already counts them inside `user` and `nice`.
CpuTicks? cpuTicksFromProcStat(String text) {
  final line = text
      .split('\n')
      .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
  if (line.isEmpty) return null;
  final fields = line
      .split(RegExp(r'\s+'))
      .skip(1)
      .take(8)
      .map(int.tryParse)
      .toList();
  if (fields.length < 8 || fields.any((v) => v == null)) return null;
  final v = fields.cast<int>();
  final user = v[0], nice = v[1], system = v[2], idle = v[3];
  final iowait = v[4], irq = v[5], softirq = v[6], steal = v[7];
  final total = user + nice + system + idle + iowait + irq + softirq + steal;
  return CpuTicks(busy: total - idle - iowait, total: total);
}

/// Builds ticks from `GetSystemTimes` (100 ns units). The kernel time includes
/// the idle time, so the total is kernel plus user.
CpuTicks? cpuTicksFromWindows({
  required int idle,
  required int kernel,
  required int user,
}) {
  if (idle < 0 || kernel < 0 || user < 0) return null;
  final total = kernel + user;
  if (idle > total) return null;
  return CpuTicks(busy: total - idle, total: total);
}

/// Builds ticks from the summed `PROCESSOR_CPU_LOAD_INFO` counters of macOS in
/// the order user, system, idle, nice (one entry per state, summed over all
/// cores).
CpuTicks? cpuTicksFromMacTotals({
  required int user,
  required int system,
  required int idle,
  required int nice,
}) {
  if (user < 0 || system < 0 || idle < 0 || nice < 0) return null;
  final total = user + system + idle + nice;
  if (total <= 0) return null;
  return CpuTicks(busy: total - idle, total: total);
}

/// The whole-machine load in percent between two readings, `0` to `100`.
/// `null` when no time passed or the readings are not in order (the counters
/// then say nothing useful yet).
double? cpuPercentBetween(CpuTicks earlier, CpuTicks later) {
  final totalDelta = later.total - earlier.total;
  if (totalDelta <= 0) return null;
  final busyDelta = later.busy - earlier.busy;
  final percent = busyDelta * 100 / totalDelta;
  return percent.clamp(0.0, 100.0).toDouble();
}

/// Whole percent of [totalMB] in use, from the total and available memory.
/// `null` when the total is unknown.
int? ramUsedPercent({required int totalMB, required int availableMB}) {
  if (totalMB <= 0) return null;
  final used = (totalMB - availableMB).clamp(0, totalMB);
  return (used * 100 / totalMB).round();
}

/// Below this much free disk space the card warns: recordings and models need
/// room, and a full volume makes a dictation fail when it is saved.
const int kOverviewDiskLowBytes = 2 * 1024 * 1024 * 1024;

/// Whether free disk space is so low that the card warns. Unknown space
/// (`null`) never warns.
bool isDiskLow(int? freeBytes) =>
    freeBytes != null && freeBytes < kOverviewDiskLowBytes;

/// Whether free memory is below [lowFraction] of total memory. The threshold
/// comes from the speech engine's pressure policy, so both agree on pressure.
bool isRamLow({
  required int totalMB,
  required int availableMB,
  required double lowFraction,
}) {
  if (totalMB <= 0) return false;
  return availableMB / totalMB < lowFraction;
}
