// Runner-owned MethodChannel bridge for the native floating button.
// Receives commands from Dart, forwards events back via InvokeMethod.

#include "floating_button_host.h"

#include <flutter/encodable_value.h>

#include <string>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.floating_button";

// Extract a double from an EncodableValue map (handles int-encoded doubles).
double GetDouble(const EncodableMap& map, const std::string& key,
                 double fallback = 0.0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* d = std::get_if<double>(&it->second)) return *d;
  if (auto* i = std::get_if<int32_t>(&it->second))
    return static_cast<double>(*i);
  if (auto* l = std::get_if<int64_t>(&it->second))
    return static_cast<double>(*l);
  return fallback;
}

int GetInt(const EncodableMap& map, const std::string& key, int fallback = 0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (auto* l = std::get_if<int64_t>(&it->second))
    return static_cast<int>(*l);
  if (auto* d = std::get_if<double>(&it->second))
    return static_cast<int>(*d);
  return fallback;
}

bool GetBool(const EncodableMap& map, const std::string& key,
             bool fallback = false) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* b = std::get_if<bool>(&it->second)) return *b;
  return fallback;
}

std::string GetString(const EncodableMap& map, const std::string& key,
                      const std::string& fallback = "") {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  return fallback;
}

FloatingButtonState ParseState(const std::string& s) {
  if (s == "recording") return FloatingButtonState::kRecording;
  if (s == "transcribing") return FloatingButtonState::kTranscribing;
  if (s == "done") return FloatingButtonState::kDone;
  if (s == "error") return FloatingButtonState::kError;
  if (s == "disabled") return FloatingButtonState::kDisabled;
  return FloatingButtonState::kIdle;
}

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

FloatingButtonHost::FloatingButtonHost(flutter::FlutterEngine* engine,
                                       HWND owner)
    : engine_(engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  OutputDebugStringW(L"[FloatingButton] Host created\n");
}

FloatingButtonHost::~FloatingButtonHost() { Destroy(); }

void FloatingButtonHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }

  if (window_) {
    window_->Destroy();
    window_.reset();
  }

  OutputDebugStringW(L"[FloatingButton] Host destroyed\n");
}

void FloatingButtonHost::RefreshTopmost() {
  if (!destroyed_ && window_) window_->RefreshTopmost();
}

// ══════════════════════════════════════════════════════════════════════
// Method call handler (Dart → C++)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "FloatingButtonHost is destroyed");
    return;
  }

  const auto& method = call.method_name();
  const auto* args = call.arguments();
  const EncodableMap* map =
      args ? std::get_if<EncodableMap>(args) : nullptr;

  // ── show ────────────────────────────────────────────────────────────
  if (method == "show") {
    if (!window_) {
      window_ = std::make_unique<FloatingButtonWindow>();

      double x = map ? GetDouble(*map, "x", 200.0) : 200.0;
      double y = map ? GetDouble(*map, "y", 200.0) : 200.0;
      int size = map ? GetInt(*map, "size", 56) : 56;

      if (!window_->Create(owner_, x, y, size)) {
        window_.reset();
        result->Error("CREATE_FAILED",
                      "Failed to create native floating button window");
        return;
      }

      // Wire callbacks (fire events to Dart).
      window_->SetClickCallback([this]() { SendEvent("onClicked"); });
      window_->SetSecondaryClickCallback(
          [this]() { SendEvent("onSecondaryClicked"); });
      window_->SetContextMenuCallback(
          [this](const std::string& id) {
            EncodableMap m;
            m[EncodableValue("id")] = EncodableValue(id);
            SendEvent("onContextMenu", EncodableValue(m));
          });
      window_->SetDragEndCallback(
          [this](double lx, double ly) {
            EncodableMap m;
            m[EncodableValue("x")] = EncodableValue(lx);
            m[EncodableValue("y")] = EncodableValue(ly);
            SendEvent("onDragEnded", EncodableValue(m));
          });
    }

    // Update position + size on re-show (settings may have changed).
    if (map) {
      double x = GetDouble(*map, "x", -1.0);
      double y = GetDouble(*map, "y", -1.0);
      int size = GetInt(*map, "size", 56);
      if (x >= 0 && y >= 0) window_->SetPosition(x, y);
      window_->SetSize(size);
    }

    window_->Show();
    result->Success();
    return;
  }

  // ── hide ────────────────────────────────────────────────────────────
  if (method == "hide") {
    if (window_) window_->Hide();
    result->Success();
    return;
  }

  // ── setState ────────────────────────────────────────────────────────
  if (method == "setState") {
    if (window_ && map) {
      auto state_str = GetString(*map, "state", "idle");
      window_->SetState(ParseState(state_str));
    }
    result->Success();
    return;
  }

  // ── setTheme ────────────────────────────────────────────────────────
  if (method == "setTheme") {
    if (window_ && map) {
      window_->SetTheme(GetBool(*map, "isDark", true));
    }
    result->Success();
    return;
  }

  // ── setPosition ─────────────────────────────────────────────────────
  if (method == "setPosition") {
    if (window_ && map) {
      window_->SetPosition(GetDouble(*map, "x"), GetDouble(*map, "y"));
    }
    result->Success();
    return;
  }

  // ── setSize ─────────────────────────────────────────────────────────
  if (method == "setSize") {
    if (window_ && map) {
      window_->SetSize(GetInt(*map, "size", 56));
    }
    result->Success();
    return;
  }

  // ── setOpacity ──────────────────────────────────────────────────────
  if (method == "setOpacity") {
    if (window_ && map) {
      window_->SetOpacity(GetDouble(*map, "opacity", 1.0));
    }
    result->Success();
    return;
  }

  // ── getPosition ─────────────────────────────────────────────────────
  // ── setContextMenuItems ──────────────────────────────────────────────
  if (method == "setContextMenuItems") {
    if (window_) {
      auto* args_map = std::get_if<EncodableMap>(call.arguments());
      if (args_map) {
        auto it = args_map->find(EncodableValue("items"));
        if (it != args_map->end()) {
          auto* list = std::get_if<flutter::EncodableList>(&it->second);
          if (list) {
            std::vector<std::pair<std::string, std::wstring>> items;
            for (auto& item_val : *list) {
              auto* item_map = std::get_if<EncodableMap>(&item_val);
              if (!item_map) continue;
              auto id_it = item_map->find(EncodableValue("id"));
              auto label_it = item_map->find(EncodableValue("label"));
              if (id_it == item_map->end() || label_it == item_map->end())
                continue;
              auto* id_str = std::get_if<std::string>(&id_it->second);
              auto* label_str = std::get_if<std::string>(&label_it->second);
              if (!id_str || !label_str) continue;
              // Convert UTF-8 label to wstring.
              int len = MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(),
                                            -1, nullptr, 0);
              std::wstring wlabel(len - 1, 0);
              MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(), -1,
                                  wlabel.data(), len);
              items.emplace_back(*id_str, std::move(wlabel));
            }
            window_->SetContextMenuItems(std::move(items));
          }
        }
      }
    }
    result->Success();
    return;
  }

  if (method == "getPosition") {
    if (window_) {
      auto [x, y] = window_->GetPosition();
      EncodableMap m;
      m[EncodableValue("x")] = EncodableValue(x);
      m[EncodableValue("y")] = EncodableValue(y);
      result->Success(EncodableValue(m));
    } else {
      result->Success();
    }
    return;
  }

  // ── destroy ─────────────────────────────────────────────────────────
  if (method == "destroy") {
    if (window_) {
      window_->Destroy();
      window_.reset();
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Events (C++ → Dart)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::SendEvent(const std::string& method,
                                   const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method,
                         std::make_unique<EncodableValue>(args));
}

void FloatingButtonHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
