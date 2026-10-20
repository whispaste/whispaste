// Offline test of the libei sender (linux/runner/eis_keyboard_sender.cc)
// against a libeis test server, without a portal or a desktop session.
//
// The sender speaks the libei client protocol on one end of a socketpair; the
// libeis server on the other end records every event it gets. The test checks
// the exact keycode order of Ctrl+V and Ctrl+Shift+C and prints the latency
// from the SendCtrlShortcut() call to the arrival of the frame at the server.
//
// Build and run with tools/linux_eis_test/run.sh. Not part of the app build.
//
// libeis has no installed header on this host (only libeis.so.1), so its few
// functions are declared here by hand. Its event type numbers are checked at
// run time against eis_event_type_to_string(), so a different libeis fails the
// test instead of silently mapping events to the wrong names.

#include <poll.h>
#include <sys/un.h>
#include <sys/socket.h>
#include <unistd.h>


#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "eis_keyboard_sender.h"

extern "C" {
struct eis;
struct eis_event;
struct eis_client;
struct eis_seat;
struct eis_device;

struct eis* eis_new(void* user_data);
void eis_unref(struct eis* eis);
int eis_setup_backend_socket(struct eis* eis, const char* name);
int eis_get_fd(struct eis* eis);
void eis_dispatch(struct eis* eis);
struct eis_event* eis_get_event(struct eis* eis);
int eis_event_get_type(struct eis_event* event);
void eis_event_unref(struct eis_event* event);
struct eis_client* eis_event_get_client(struct eis_event* event);
struct eis_seat* eis_event_get_seat(struct eis_event* event);
struct eis_device* eis_event_get_device(struct eis_event* event);
bool eis_event_seat_has_capability(struct eis_event* event, int cap);
uint32_t eis_event_keyboard_get_key(struct eis_event* event);
bool eis_event_keyboard_get_key_is_press(struct eis_event* event);
void eis_client_connect(struct eis_client* client);
struct eis_seat* eis_client_new_seat(struct eis_client* client,
                                     const char* name);
void eis_seat_configure_capability(struct eis_seat* seat, int cap);
void eis_seat_add(struct eis_seat* seat);
struct eis_device* eis_seat_new_device(struct eis_seat* seat);
void eis_device_configure_name(struct eis_device* device, const char* name);
void eis_device_configure_capability(struct eis_device* device, int cap);
void eis_device_add(struct eis_device* device);
void eis_device_resume(struct eis_device* device);
const char* eis_event_type_to_string(int type);
}

namespace {

// libeis event types (values as reported by eis_event_type_to_string).
struct EisType {
  int value;
  const char* name;
};
constexpr EisType kClientConnect = {1, "EIS_EVENT_CLIENT_CONNECT"};
constexpr EisType kClientDisconnect = {2, "EIS_EVENT_CLIENT_DISCONNECT"};
constexpr EisType kSeatBind = {3, "EIS_EVENT_SEAT_BIND"};
constexpr EisType kDeviceClosed = {4, "EIS_EVENT_DEVICE_CLOSED"};
constexpr EisType kFrame = {100, "EIS_EVENT_FRAME"};
constexpr EisType kDeviceStartEmulating = {200,
                                           "EIS_EVENT_DEVICE_START_EMULATING"};
constexpr EisType kDeviceStopEmulating = {201,
                                          "EIS_EVENT_DEVICE_STOP_EMULATING"};
constexpr EisType kKeyboardKey = {700, "EIS_EVENT_KEYBOARD_KEY"};
// Same bit as EI_DEVICE_CAP_KEYBOARD in libei.h.
constexpr int kEisDeviceCapKeyboard = 1 << 2;

// False when a constant above does not match this libeis build.
bool CheckEisTypes() {
  const EisType all[] = {kClientConnect, kClientDisconnect, kSeatBind,
                         kDeviceClosed,  kFrame,            kDeviceStartEmulating,
                         kDeviceStopEmulating, kKeyboardKey};
  for (const EisType& t : all) {
    const char* got = eis_event_type_to_string(t.value);
    if (got == nullptr || std::strcmp(got, t.name) != 0) {
      std::fprintf(stderr, "FAIL: libeis type %d is '%s', expected '%s'\n",
                   t.value, got ? got : "(null)", t.name);
      return false;
    }
  }
  return true;
}

constexpr uint32_t kKeyLeftCtrl = 29;
constexpr uint32_t kKeyLeftShift = 42;
constexpr uint32_t kKeyC = 46;
constexpr uint32_t kKeyV = 47;

using Clock = std::chrono::steady_clock;

struct Record {
  int type;
  uint32_t key;
  bool press;
  Clock::time_point at;
};

class Recorder {
 public:
  void Add(Record r) {
    std::lock_guard<std::mutex> lock(mutex_);
    records_.push_back(r);
  }
  std::vector<Record> Snapshot() {
    std::lock_guard<std::mutex> lock(mutex_);
    return records_;
  }
  size_t Size() {
    std::lock_guard<std::mutex> lock(mutex_);
    return records_.size();
  }

 private:
  std::mutex mutex_;
  std::vector<Record> records_;
};

// Runs the libeis server on its own thread until [stop] is set.
void ServerLoop(eis* server, Recorder* rec, std::atomic<bool>* stop) {
  bool device_created = false;
  while (!stop->load()) {
    pollfd pfd = {eis_get_fd(server), POLLIN, 0};
    if (poll(&pfd, 1, 20) > 0) eis_dispatch(server);
    while (eis_event* ev = eis_get_event(server)) {
      const int type = eis_event_get_type(ev);
      const auto now = Clock::now();
      switch (type) {
        case kClientConnect.value: {
          eis_client* client = eis_event_get_client(ev);
          eis_client_connect(client);
          eis_seat* seat = eis_client_new_seat(client, "seat0");
          eis_seat_configure_capability(seat, kEisDeviceCapKeyboard);
          eis_seat_add(seat);
          break;
        }
        case kSeatBind.value: {
          if (!device_created &&
              eis_event_seat_has_capability(ev, kEisDeviceCapKeyboard)) {
            eis_seat* seat = eis_event_get_seat(ev);
            eis_device* dev = eis_seat_new_device(seat);
            eis_device_configure_name(dev, "whispaste-eis-test-keyboard");
            eis_device_configure_capability(dev, kEisDeviceCapKeyboard);
            eis_device_add(dev);
            eis_device_resume(dev);
            device_created = true;
          }
          rec->Add({type, 0, false, now});
          break;
        }
        case kKeyboardKey.value:
          rec->Add({type, eis_event_keyboard_get_key(ev),
                    eis_event_keyboard_get_key_is_press(ev), now});
          break;
        case kFrame.value:
        case kDeviceStartEmulating.value:
        case kDeviceStopEmulating.value:
        case kClientDisconnect.value:
        case kDeviceClosed.value:
          rec->Add({type, 0, false, now});
          break;
        default:
          break;
      }
      eis_event_unref(ev);
    }
  }
  eis_unref(server);
}

// Expected key sequence as (keycode, press) pairs, the same order the sender
// uses: modifiers down, key down/up, modifiers up.
std::vector<std::pair<uint32_t, bool>> ExpectedKeys(uint32_t key, bool shift) {
  std::vector<std::pair<uint32_t, bool>> seq = {{kKeyLeftCtrl, true}};
  if (shift) seq.push_back({kKeyLeftShift, true});
  seq.push_back({key, true});
  seq.push_back({key, false});
  if (shift) seq.push_back({kKeyLeftShift, false});
  seq.push_back({kKeyLeftCtrl, false});
  return seq;
}

// Waits until the server has recorded [count] records or [timeout] passes.
bool WaitForRecords(Recorder* rec, size_t count,
                    std::chrono::milliseconds timeout) {
  const auto deadline = Clock::now() + timeout;
  while (rec->Size() < count) {
    if (Clock::now() > deadline) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return true;
}

}  // namespace

int main() {
  if (!EisKeyboardSender::IsLibeiAvailable()) {
    std::fprintf(stderr, "FAIL: libei.so.1 cannot be loaded\n");
    return 2;
  }

  if (!CheckEisTypes()) return 2;

  // libeis listens on $XDG_RUNTIME_DIR/<name>; the sender connects to it, so
  // the sender gets an ordinary connected socket like from the portal.
  char runtime_dir[] = "/tmp/wp-eis-test-XXXXXX";
  if (mkdtemp(runtime_dir) == nullptr) {
    std::fprintf(stderr, "FAIL: mkdtemp\n");
    return 2;
  }
  setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
  const std::string socket_path =
      std::string(runtime_dir) + "/whispaste-eis-test";

  eis* server = eis_new(nullptr);
  if (eis_setup_backend_socket(server, "whispaste-eis-test") != 0) {
    std::fprintf(stderr, "FAIL: eis_setup_backend_socket\n");
    return 2;
  }
  int client_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  sockaddr_un addr = {};
  addr.sun_family = AF_UNIX;
  std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
  if (client_fd < 0 ||
      connect(client_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) !=
          0) {
    std::fprintf(stderr, "FAIL: connect to %s\n", socket_path.c_str());
    return 2;
  }

  Recorder rec;
  std::atomic<bool> stop{false};
  std::thread server_thread(ServerLoop, server, &rec, &stop);

  // The sender takes ownership of client_fd.
  EisKeyboardSender sender(client_fd);
  const bool ready = sender.WaitUntilReady(3000);
  if (!ready) {
    std::fprintf(stderr, "FAIL: keyboard device not ready within 3 s\n");
    stop.store(true);
    server_thread.join();
    return 1;
  }
  std::printf("handshake: keyboard device ready\n");

  struct Case {
    const char* name;
    uint32_t key;
    bool shift;
  };
  const Case cases[] = {
      {"Ctrl+V", kKeyV, false},     {"Ctrl+V", kKeyV, false},
      {"Ctrl+V", kKeyV, false},     {"Ctrl+Shift+V", kKeyV, true},
      {"Ctrl+Shift+C", kKeyC, true}, {"Ctrl+C", kKeyC, false},
  };

  int failures = 0;
  std::vector<double> latencies_ms;
  // Records before the first shortcut (handshake) are skipped.
  size_t offset = rec.Size();

  for (const Case& c : cases) {
    const auto expected = ExpectedKeys(c.key, c.shift);
    // START_EMULATING + keys + FRAME + STOP_EMULATING
    const size_t want = offset + 1 + expected.size() + 2;
    const auto t0 = Clock::now();
    const bool sent = sender.SendCtrlShortcut(c.key, c.shift);
    if (!sent) {
      std::printf("FAIL %s: SendCtrlShortcut returned false\n", c.name);
      ++failures;
      break;
    }
    if (!WaitForRecords(&rec, want, std::chrono::milliseconds(2000))) {
      std::printf("FAIL %s: server saw %zu of %zu records\n", c.name,
                  rec.Size() - offset, want - offset);
      ++failures;
      break;
    }
    const auto recs = rec.Snapshot();
    std::vector<std::pair<uint32_t, bool>> got;
    int seen_start = 0, seen_stop = 0, seen_frame = 0;
    Clock::time_point frame_at{};
    for (size_t i = offset; i < want; ++i) {
      const Record& r = recs[i];
      if (r.type == kKeyboardKey.value) got.push_back({r.key, r.press});
      if (r.type == kDeviceStartEmulating.value) ++seen_start;
      if (r.type == kDeviceStopEmulating.value) ++seen_stop;
      if (r.type == kFrame.value) {
        ++seen_frame;
        frame_at = r.at;
      }
    }
    const bool order_ok = got == expected && seen_start == 1 &&
                          seen_stop == 1 && seen_frame == 1;
    if (!order_ok) {
      std::printf("FAIL %s: unexpected sequence (keys=%zu, start=%d, "
                  "frame=%d, stop=%d)\n",
                  c.name, got.size(), seen_start, seen_frame, seen_stop);
      ++failures;
    } else {
      const double ms =
          std::chrono::duration<double, std::milli>(frame_at - t0).count();
      latencies_ms.push_back(ms);
      std::printf("PASS %-14s keys=%s latency=%.3f ms\n", c.name,
                  c.shift ? "ctrl+shift" : "ctrl", ms);
    }
    offset = want;
  }

  // Disconnect path: a closed sender must refuse to send.
  sender.Close();
  if (sender.SendCtrlShortcut(kKeyV, false)) {
    std::printf("FAIL: send after Close succeeded\n");
    ++failures;
  } else {
    std::printf("PASS send after Close refused\n");
  }

  stop.store(true);
  server_thread.join();
  rmdir(runtime_dir);

  if (!latencies_ms.empty()) {
    std::sort(latencies_ms.begin(), latencies_ms.end());
    std::printf("latency over %zu shortcuts: min=%.3f median=%.3f max=%.3f ms\n",
                latencies_ms.size(), latencies_ms.front(),
                latencies_ms[latencies_ms.size() / 2], latencies_ms.back());
  }
  std::printf("%s (%d failure(s))\n", failures == 0 ? "ALL PASS" : "FAILED",
              failures);
  return failures == 0 ? 0 : 1;
}
