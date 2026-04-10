// Runner-owned MethodChannel bridge for the native floating overlay.
// Receives snapshot updates from Dart, forwards user events back.

#include "floating_overlay_host.h"

#include <flutter/encodable_value.h>

#include <string>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.floating_overlay";

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

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (len <= 0) return L"";
  std::wstring result(len - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &result[0], len);
  return result;
}

OverlayVisualState ParseState(const std::string& s) {
  if (s == "recording") return OverlayVisualState::kRecording;
  if (s == "transcribing") return OverlayVisualState::kTranscribing;
  if (s == "processing") return OverlayVisualState::kProcessing;
  if (s == "done") return OverlayVisualState::kDone;
  if (s == "error") return OverlayVisualState::kError;
  return OverlayVisualState::kRecording;
}

OverlayAnchorMode ParseAnchor(const std::string& s) {
  if (s == "top_center" || s == "topCenter") return OverlayAnchorMode::kTopCenter;
  if (s == "bottom_center" || s == "bottomCenter") return OverlayAnchorMode::kBottomCenter;
  if (s == "custom" || s == "topLeft") return OverlayAnchorMode::kTopLeft;
  return OverlayAnchorMode::kTopCenter;
}

OverlaySnapshot ParseSnapshot(const EncodableMap& map) {
  OverlaySnapshot snap;
  snap.visible = GetBool(map, "visible", false);
  snap.state = ParseState(GetString(map, "state", "recording"));
  snap.is_dark = GetBool(map, "isDark", true);
  snap.compact = GetBool(map, "compact", false);
  snap.label = Utf8ToWide(GetString(map, "label"));
  snap.elapsed = Utf8ToWide(GetString(map, "elapsed"));
  snap.hint = Utf8ToWide(GetString(map, "hint"));
  snap.transcript = Utf8ToWide(GetString(map, "transcript"));
  snap.error_message = Utf8ToWide(GetString(map, "errorMessage"));
  snap.done_message = Utf8ToWide(GetString(map, "doneMessage"));
  snap.processing_label = Utf8ToWide(GetString(map, "processingLabel"));
  snap.privacy_mode = Utf8ToWide(GetString(map, "privacyMode"));
  snap.show_retry = GetBool(map, "showRetry", false);
  snap.progress = static_cast<float>(GetDouble(map, "progress", 0.0));
  return snap;
}

}  // namespace

// ═══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ═══════════════════════════════════════════════════════════════════════

FloatingOverlayHost::FloatingOverlayHost(flutter::FlutterEngine* engine,
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

  OutputDebugStringW(L"[FloatingOverlay] Host created\n");
}

FloatingOverlayHost::~FloatingOverlayHost() { Destroy(); }

void FloatingOverlayHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }

  if (window_) {
    window_->Destroy();
    window_.reset();
  }

  OutputDebugStringW(L"[FloatingOverlay] Host destroyed\n");
}

// ═══════════════════════════════════════════════════════════════════════
// Method call handler (Dart → C++)
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "FloatingOverlayHost is destroyed");
    return;
  }

  const auto& method = call.method_name();
  const auto* args = call.arguments();
  const EncodableMap* map =
      args ? std::get_if<EncodableMap>(args) : nullptr;

  // ── updateSnapshot ──────────────────────────────────────────────────
  if (method == "updateSnapshot") {
    if (!window_) {
      window_ = std::make_unique<FloatingOverlayWindow>();
      if (!window_->Create(owner_)) {
        window_.reset();
        result->Error("CREATE_FAILED",
                      "Failed to create native floating overlay window");
        return;
      }

      // Wire callbacks
      window_->SetDragEndCallback(
          [this](double x, double y, const std::string& anchor) {
            EncodableMap m;
            m[EncodableValue("x")] = EncodableValue(x);
            m[EncodableValue("y")] = EncodableValue(y);
            m[EncodableValue("anchorMode")] = EncodableValue(anchor);
            SendEvent("onDragEnded", EncodableValue(m));
          });
      window_->SetCloseCallback([this]() { SendEvent("onCloseClicked"); });
      window_->SetBodyClickCallback(
          [this]() { SendEvent("onBodyClicked"); });
      window_->SetRetryCallback([this]() { SendEvent("onRetryClicked"); });
      window_->SetContextMenuCallback(
          [this](const std::string& action) {
            EncodableMap m;
            m[EncodableValue("action")] = EncodableValue(action);
            SendEvent("onContextMenu", EncodableValue(m));
          });

      // Apply any position that arrived before the window was created.
      if (pending_position_) {
        window_->SetPosition(pending_position_->x, pending_position_->y,
                             pending_position_->anchor);
        pending_position_ = std::nullopt;
      }
    }

    if (map) {
      window_->UpdateSnapshot(ParseSnapshot(*map));
    }
    result->Success();
    return;
  }

  // ── setAudioLevel ───────────────────────────────────────────────────
  if (method == "setAudioLevel") {
    if (window_ && map) {
      window_->SetAudioLevel(GetDouble(*map, "level", 0.0));
    }
    result->Success();
    return;
  }

  // ── setPosition ─────────────────────────────────────────────────────
  if (method == "setPosition") {
    if (map) {
      double x = GetDouble(*map, "x", 0.0);
      double y = GetDouble(*map, "y", 0.0);
      OverlayAnchorMode anchor =
          ParseAnchor(GetString(*map, "anchorMode", "top_center"));
      if (window_) {
        window_->SetPosition(x, y, anchor);
      } else {
        // Window not yet created — store for application after creation.
        pending_position_ = {x, y, anchor};
      }
    }
    result->Success();
    return;
  }

  // ── setContextMenuItems ─────────────────────────────────────────────
  if (method == "setContextMenuItems") {
    if (window_ && args) {
      if (auto* list = std::get_if<EncodableList>(args)) {
        std::vector<OverlayContextMenuItem> items;
        for (const auto& item : *list) {
          if (auto* item_map = std::get_if<EncodableMap>(&item)) {
            OverlayContextMenuItem mi;
            mi.id = Utf8ToWide(GetString(*item_map, "id"));
            mi.label = Utf8ToWide(GetString(*item_map, "label"));
            items.push_back(std::move(mi));
          }
        }
        window_->SetContextMenuItems(std::move(items));
      }
    }
    result->Success();
    return;
  }

  // ── setOpacity ───────────────────────────────────────────────────────
  if (method == "setOpacity") {
    if (window_ && map) {
      window_->SetOpacity(GetDouble(*map, "opacity", 1.0));
    }
    result->Success();
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

// ═══════════════════════════════════════════════════════════════════════
// Events (C++ → Dart)
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::SendEvent(const std::string& method,
                                     const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method,
                         std::make_unique<EncodableValue>(args));
}

void FloatingOverlayHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
