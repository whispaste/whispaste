#include "clipboard_receipt.h"

#include <utility>

#include "clipboard_hint.h"

int ClipboardReceipt::ScopedSelfRead::depth_ = 0;

ClipboardReceipt::ClipboardReceipt(GtkClipboard* clipboard)
    : clipboard_(clipboard) {}

ClipboardReceipt::~ClipboardReceipt() {
  Cancel();
  // GTK keeps serving the text after the host is gone; the payload just no
  // longer reports back.
  if (current_ != nullptr) current_->owner = nullptr;
}

bool ClipboardReceipt::Write(const std::string& text) {
  ResolvePending("superseded");
  active_ = false;
  keystroke_posted_ = false;
  read_ = false;
  auto* payload = new Payload{this, text};
  // Set before taking the clipboard: GTK clears an earlier payload of ours
  // inside the call, and that clear must not count as a takeover.
  current_ = payload;
  if (!SetClipboardHiddenWithData(clipboard_, OnGet, OnClear, payload)) {
    current_ = nullptr;
    delete payload;
    return false;
  }
  active_ = true;
  return true;
}

void ClipboardReceipt::MarkKeystrokePosted() { keystroke_posted_ = active_; }

void ClipboardReceipt::Wait(Resolve resolve) {
  if (read_) {
    resolve("read");
    return;
  }
  if (!active_) {
    resolve("lost");
    return;
  }
  ResolvePending("superseded");
  pending_ = std::move(resolve);
}

std::string ClipboardReceipt::RestoreIfOwner(const std::string& text) {
  const bool owner = active_;
  active_ = false;
  ResolvePending(owner ? "superseded" : "lost");
  if (!owner) return "not_owner";
  return SetClipboardTextHidden(clipboard_, text) ? "restored" : "failed";
}

void ClipboardReceipt::Cancel() { ResolvePending("superseded"); }

void ClipboardReceipt::ResolvePending(const char* status) {
  if (!pending_) return;
  // Moved out first: the callback may arm the next wait.
  Resolve resolve = std::move(pending_);
  pending_ = nullptr;
  resolve(status);
}

// static
void ClipboardReceipt::OnGet(GtkClipboard* /*clipboard*/,
                             GtkSelectionData* data, guint info,
                             gpointer user_data) {
  auto* payload = static_cast<Payload*>(user_data);
  SetHiddenClipboardSelection(data, info, payload->text);
  ClipboardReceipt* self = payload->owner;
  if (info != kClipboardTextInfo || ScopedSelfRead::Active() ||
      self == nullptr ||
      self->current_ != payload || !self->active_ ||
      !self->keystroke_posted_ || self->read_) {
    return;
  }
  self->read_ = true;
  self->ResolvePending("read");
}

// static
void ClipboardReceipt::OnClear(GtkClipboard* /*clipboard*/,
                               gpointer user_data) {
  auto* payload = static_cast<Payload*>(user_data);
  ClipboardReceipt* self = payload->owner;
  if (self != nullptr && self->current_ == payload) {
    // Another writer (or WhisPaste's own next write) took the clipboard.
    self->current_ = nullptr;
    self->active_ = false;
    self->ResolvePending("lost");
  }
  delete payload;
}
