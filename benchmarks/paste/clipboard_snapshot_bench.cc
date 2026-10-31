// Latency benchmark of the full clipboard snapshot (P1.1) against the old
// plain-text read, on a real X display. A forked process owns the clipboard
// with the payload of one case at a time (like another app would); the parent
// measures VORHER = reading the text form only (the former Dart
// Clipboard.getData path) and NACHHER = ClipboardSnapshot::Take plus Restore.
// Prints median and p95 per case; nothing is asserted, so no budget can fail
// a test run. Run via benchmarks/paste/clipboard_snapshot_bench.sh.
#include "clipboard_snapshot.h"

#include <poll.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

struct Payload {
  const char* type;  // GTK target name, e.g. "UTF8_STRING" or "image/png"
  std::string data;
};

struct BenchCase {
  const char* name;
  std::vector<Payload> payloads;
};

std::string Repeat(const std::string& unit, size_t bytes) {
  std::string out;
  out.reserve(bytes + unit.size());
  while (out.size() < bytes) out += unit;
  out.resize(bytes);
  return out;
}

// Incompressible bytes with a PNG signature, so the transfer size matches a
// real image of that size. Fixed seed keeps every run on the same payload.
std::string PngLikeBytes(size_t bytes) {
  std::mt19937 rng(20261030);
  std::string out(bytes, '\0');
  for (char& c : out) c = static_cast<char>(rng() & 0xff);
  static const char kSignature[] = "\x89PNG\r\n\x1a\n";
  std::memcpy(&out[0], kSignature, sizeof(kSignature) - 1);
  return out;
}

std::vector<BenchCase> BuildCases() {
  // ASCII-only where a case cuts text at a byte count, so no UTF-8 sequence
  // is split and GTK's text read stays valid.
  const std::string sentence =
      "Grüße aus dem Diktat — WhisPaste, ein kurzer Satz für die Messung. ";
  const std::string ascii_line = "Diktat-Satz fuer die Messung der Zwischenablage. ";
  const std::string html_unit =
      "<p><b>Diktat</b> mit <i>Formatierung</i> und <a href=\"https://example.org\">Link</a>.</p>";
  return {
      {"text-small", {{"UTF8_STRING", sentence}}},
      {"text-100kb", {{"UTF8_STRING", Repeat(ascii_line, 100 * 1024)}}},
      {"html+text", {{"text/html", Repeat(html_unit, 8 * 1024)},
                     {"UTF8_STRING", Repeat(ascii_line, 1024)}}},
      {"png-1mb+text", {{"image/png", PngLikeBytes(1024 * 1024)},
                        {"UTF8_STRING", sentence}}},
      {"png-8mb+text", {{"image/png", PngLikeBytes(8 * 1024 * 1024)},
                        {"UTF8_STRING", sentence}}},
  };
}

// --- Owner process: serves the case named by the command byte. ---

const BenchCase* g_owned = nullptr;

void GetPayload(GtkClipboard* /*clipboard*/, GtkSelectionData* data,
                guint info, gpointer /*user_data*/) {
  const Payload& payload = g_owned->payloads[info];
  gtk_selection_data_set(
      data, gdk_atom_intern(payload.type, FALSE), 8,
      reinterpret_cast<const guchar*>(payload.data.data()),
      static_cast<gint>(payload.data.size()));
}

struct Owner {
  const std::vector<BenchCase>* cases;
  int replies;
  GtkClipboard* clipboard;
  GMainLoop* loop;
};

// Command 'a' + index takes the clipboard with that case; 'q' quits.
// Answers 'd' when the owner holds the clipboard, 'e' otherwise.
gboolean OnCommand(GIOChannel* source, GIOCondition /*condition*/,
                   gpointer data) {
  auto* owner = static_cast<Owner*>(data);
  char command = 0;
  if (read(g_io_channel_unix_get_fd(source), &command, 1) != 1 ||
      command == 'q') {
    g_main_loop_quit(owner->loop);
    return G_SOURCE_REMOVE;
  }
  const size_t index = static_cast<size_t>(command - 'a');
  char reply = 'e';
  if (index < owner->cases->size()) {
    const BenchCase& bench_case = (*owner->cases)[index];
    std::vector<GtkTargetEntry> entries;
    for (size_t i = 0; i < bench_case.payloads.size(); ++i) {
      entries.push_back({const_cast<gchar*>(bench_case.payloads[i].type), 0,
                         static_cast<guint>(i)});
    }
    g_owned = &bench_case;
    if (gtk_clipboard_set_with_data(owner->clipboard, entries.data(),
                                    static_cast<guint>(entries.size()),
                                    GetPayload, nullptr, nullptr)) {
      reply = 'd';
    }
  }
  // Flush so the X server has the ownership before the parent is answered.
  gdk_display_flush(gdk_display_get_default());
  if (write(owner->replies, &reply, 1) != 1) reply = 'e';
  return G_SOURCE_CONTINUE;
}

int OwnerProcess(const std::vector<BenchCase>& cases, int commands,
                 int replies) {
  gtk_init(nullptr, nullptr);
  Owner owner{&cases, replies, gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
              g_main_loop_new(nullptr, FALSE)};
  GIOChannel* channel = g_io_channel_unix_new(commands);
  g_io_add_watch(channel, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP),
                 OnCommand, &owner);
  g_main_loop_run(owner.loop);
  g_io_channel_unref(channel);
  g_main_loop_unref(owner.loop);
  return 0;
}

// --- Parent: WhisPaste side. ---

double Ms(Clock::time_point start, Clock::time_point end) {
  return std::chrono::duration<double, std::milli>(end - start).count();
}

// Asks the owner to take the clipboard with [command]; outside the timings.
bool AskOwner(int commands, int replies, char command) {
  if (write(commands, &command, 1) != 1) return false;
  const Clock::time_point deadline = Clock::now() + std::chrono::seconds(20);
  while (Clock::now() < deadline) {
    g_main_context_iteration(nullptr, FALSE);  // handles SelectionClear
    pollfd pfd{replies, POLLIN, 0};
    if (poll(&pfd, 1, 1) > 0) {
      char reply = 0;
      return read(replies, &reply, 1) == 1 && reply == 'd';
    }
  }
  return false;
}

// VORHER: the text form only, as the old Dart read did.
double MeasureOldRead(GtkClipboard* clipboard, size_t* length) {
  const Clock::time_point start = Clock::now();
  gchar* text = gtk_clipboard_wait_for_text(clipboard);
  const Clock::time_point end = Clock::now();
  *length = text != nullptr ? std::strlen(text) : 0;
  g_free(text);
  return Ms(start, end);
}

struct Sample {
  double snapshot_ms = 0;
  double restore_ms = 0;
  bool saved = false;
  int formats = 0;
  int64_t bytes = 0;
};

// NACHHER: full snapshot, then the restore that hands the data back to GTK.
Sample MeasureSnapshot(ClipboardSnapshot& snapshot) {
  Sample sample;
  ClipboardSnapshot::Result result;
  bool done = false;
  const Clock::time_point start = Clock::now();
  snapshot.Take([&](const ClipboardSnapshot::Result& r) {
    result = r;
    done = true;
  });
  const Clock::time_point deadline = Clock::now() + std::chrono::seconds(20);
  while (!done && Clock::now() < deadline) {
    g_main_context_iteration(nullptr, TRUE);
  }
  const Clock::time_point taken = Clock::now();
  sample.snapshot_ms = Ms(start, taken);
  sample.saved = done && result.status == "saved";
  sample.formats = result.formats;
  sample.bytes = result.bytes;
  if (sample.saved) {
    const Clock::time_point restore_start = Clock::now();
    snapshot.Restore();
    sample.restore_ms = Ms(restore_start, Clock::now());
  }
  return sample;
}

struct Stats {
  double median = 0;
  double p95 = 0;
};

// Nearest-rank p95; the median is the middle value, or the mean of the two.
Stats Summarize(std::vector<double> values) {
  Stats stats;
  if (values.empty()) return stats;
  std::sort(values.begin(), values.end());
  const size_t n = values.size();
  stats.median = n % 2 == 1 ? values[n / 2]
                            : (values[n / 2 - 1] + values[n / 2]) / 2.0;
  const size_t rank = static_cast<size_t>(std::ceil(0.95 * n));
  stats.p95 = values[std::min(n, std::max<size_t>(rank, 1)) - 1];
  return stats;
}

}  // namespace

int main(int argc, char** argv) {
  int iterations = argc > 1 ? std::atoi(argv[1]) : 30;
  if (iterations <= 0) iterations = 30;
  const int kWarmup = 3;
  const std::vector<BenchCase> cases = BuildCases();

  int to_owner[2];
  int to_parent[2];
  if (pipe(to_owner) != 0 || pipe(to_parent) != 0) return 2;
  const pid_t pid = fork();
  if (pid < 0) return 2;
  if (pid == 0) {
    close(to_owner[1]);
    close(to_parent[0]);
    _exit(OwnerProcess(cases, to_owner[0], to_parent[1]));
  }
  close(to_owner[0]);
  close(to_parent[1]);
  const int commands = to_owner[1];
  const int replies = to_parent[0];

  gtk_init(nullptr, nullptr);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  ClipboardSnapshot snapshot(clipboard);

  std::printf("clipboard snapshot benchmark: %d iterations per case "
              "(+%d warm-up), GTK %d.%d.%d, GDK_BACKEND=x11\n",
              iterations, kWarmup, gtk_get_major_version(),
              gtk_get_minor_version(), gtk_get_micro_version());
  std::printf("%-14s | %-22s | %-22s | %-22s | %s\n", "case",
              "VORHER text read ms", "NACHHER snapshot ms",
              "NACHHER restore ms", "saved / formats / KiB");
  std::printf("%-14s | %-10s %-11s | %-10s %-11s | %-10s %-11s |\n", "",
              "median", "p95", "median", "p95", "median", "p95");

  int errors = 0;
  for (size_t i = 0; i < cases.size(); ++i) {
    const char command = static_cast<char>('a' + i);
    if (!AskOwner(commands, replies, command)) {
      std::fprintf(stderr, "owner did not take the clipboard: %s\n",
                   cases[i].name);
      ++errors;
      continue;
    }

    std::vector<double> old_ms;
    size_t text_length = 0;
    for (int n = 0; n < kWarmup + iterations; ++n) {
      const double ms = MeasureOldRead(clipboard, &text_length);
      if (n >= kWarmup) old_ms.push_back(ms);
    }

    std::vector<double> snap_ms;
    std::vector<double> restore_ms;
    int saved = 0;
    Sample last;
    for (int n = 0; n < kWarmup + iterations; ++n) {
      // Restores hand the clipboard to WhisPaste; the owner takes it back
      // here, outside the timings, so every snapshot reads from the owner.
      if (n > 0 && !AskOwner(commands, replies, command)) {
        ++errors;
        break;
      }
      const Sample sample = MeasureSnapshot(snapshot);
      if (n < kWarmup) continue;
      snap_ms.push_back(sample.snapshot_ms);
      if (sample.saved) {
        ++saved;
        restore_ms.push_back(sample.restore_ms);
        last = sample;
      }
    }

    const Stats old_stats = Summarize(old_ms);
    const Stats snap_stats = Summarize(snap_ms);
    const Stats restore_stats = Summarize(restore_ms);
    std::printf("%-14s | %-10.2f %-11.2f | %-10.2f %-11.2f | %-10.3f %-11.3f |"
                " %d/%d / %d / %.0f\n",
                cases[i].name, old_stats.median, old_stats.p95,
                snap_stats.median, snap_stats.p95, restore_stats.median,
                restore_stats.p95, saved, iterations, last.formats,
                static_cast<double>(last.bytes) / 1024.0);
    if (saved != iterations) ++errors;
  }

  if (write(commands, "q", 1) != 1) ++errors;
  int child = 0;
  waitpid(pid, &child, 0);
  if (errors != 0) {
    std::fprintf(stderr, "%d problem(s): see the rows marked above\n", errors);
    return 1;
  }
  return 0;
}
