#include "clipboard_snapshot.h"

#include <cstring>
#include <utility>

#include "clipboard_hint.h"
#include "clipboard_receipt.h"

namespace {

// A huge image or an owner that answers slowly must not stall the paste.
constexpr int64_t kSnapshotByteLimit = 64 * 1024 * 1024;
constexpr guint kSnapshotTimeBudgetMs = 1500;

// What GTK serves after the restore; freed by the clear callback.
struct RestorePayload {
  std::vector<ClipboardSnapshot::Target> targets;
};

void GetRestored(GtkClipboard* /*clipboard*/, GtkSelectionData* data,
                 guint info, gpointer user_data) {
  auto* payload = static_cast<RestorePayload*>(user_data);
  if (info >= payload->targets.size()) {
    // Klipper compares the hint data with "secret".
    static const char kSecret[] = "secret";
    gtk_selection_data_set(data,
                           gdk_atom_intern_static_string(kClipboardHintTarget),
                           8, reinterpret_cast<const guchar*>(kSecret),
                           sizeof(kSecret) - 1);
    return;
  }
  const ClipboardSnapshot::Target& target = payload->targets[info];
  gtk_selection_data_set(
      data, target.type, target.format,
      reinterpret_cast<const guchar*>(target.data.data()),
      static_cast<gint>(target.data.size()));
}

void ClearRestored(GtkClipboard* /*clipboard*/, gpointer user_data) {
  delete static_cast<RestorePayload*>(user_data);
}

bool IsTextTarget(GdkAtom atom) {
  gchar* name = gdk_atom_name(atom);
  const bool text = name != nullptr &&
                    (strcmp(name, "UTF8_STRING") == 0 ||
                     strcmp(name, "text/plain;charset=utf-8") == 0);
  g_free(name);
  return text;
}

}  // namespace

struct ClipboardSnapshot::Job {
  ClipboardSnapshot* owner;
  Done done;
  std::vector<GdkAtom> pending;
  size_t next = 0;
  std::vector<Target> got;
  int64_t bytes = 0;
  bool finished = false;
  guint timer = 0;
};

namespace {

// Callbacks hold the job through a heap-allocated shared pointer, so a late
// answer after the time budget finds the finished job instead of freed memory.
using JobHolder = std::shared_ptr<ClipboardSnapshot::Job>;

JobHolder TakeHolder(gpointer user_data) {
  auto* holder = static_cast<JobHolder*>(user_data);
  JobHolder job = *holder;
  delete holder;
  return job;
}

void DeleteHolder(gpointer user_data) {
  delete static_cast<JobHolder*>(user_data);
}

}  // namespace

ClipboardSnapshot::ClipboardSnapshot(GtkClipboard* clipboard)
    : clipboard_(clipboard) {}

ClipboardSnapshot::~ClipboardSnapshot() {
  if (job_) {
    job_->owner = nullptr;
    job_->finished = true;
    if (job_->timer != 0) g_source_remove(job_->timer);
    job_->timer = 0;
  }
}

// static
bool ClipboardSnapshot::IsMetaTarget(const char* name) {
  static const char* const kMeta[] = {
      "TARGETS",          "TIMESTAMP",        "MULTIPLE",
      "SAVE_TARGETS",     "DELETE",           "INSERT_PROPERTY",
      "INSERT_SELECTION", kClipboardHintTarget,
  };
  for (const char* meta : kMeta) {
    if (strcmp(name, meta) == 0) return true;
  }
  return false;
}

void ClipboardSnapshot::Take(Done done) {
  if (job_) Finish(job_, "failed");
  Discard();
  auto job = std::make_shared<Job>();
  job->owner = this;
  job->done = std::move(done);
  job_ = job;
  job->timer = g_timeout_add_full(G_PRIORITY_DEFAULT, kSnapshotTimeBudgetMs,
                                  OnTimeout, new JobHolder(job), DeleteHolder);
  // WhisPaste may still own the clipboard (an earlier transcript); GTK then
  // answers through our own get callback, which is no paste receipt.
  ClipboardReceipt::ScopedSelfRead self_read;
  gtk_clipboard_request_targets(clipboard_, OnTargets, new JobHolder(job));
}

bool ClipboardSnapshot::Restore() {
  if (targets_.empty()) return false;
  auto* payload = new RestorePayload{std::move(targets_)};
  targets_.clear();
  GtkTargetList* list = gtk_target_list_new(nullptr, 0);
  for (size_t i = 0; i < payload->targets.size(); ++i) {
    gtk_target_list_add(list, payload->targets[i].target, 0,
                        static_cast<guint>(i));
  }
  gtk_target_list_add(list, gdk_atom_intern_static_string(kClipboardHintTarget),
                      0, static_cast<guint>(payload->targets.size()));
  gint count = 0;
  GtkTargetEntry* entries = gtk_target_table_new_from_list(list, &count);
  gtk_target_list_unref(list);
  const gboolean owned =
      gtk_clipboard_set_with_data(clipboard_, entries, static_cast<guint>(count),
                                  GetRestored, ClearRestored, payload);
  gtk_target_table_free(entries, count);
  if (!owned) delete payload;
  return owned;
}

void ClipboardSnapshot::Discard() { targets_.clear(); }

// static
void ClipboardSnapshot::OnTargets(GtkClipboard* /*clipboard*/, GdkAtom* atoms,
                                  gint count, gpointer user_data) {
  JobHolder job = TakeHolder(user_data);
  if (job->finished || job->owner == nullptr) return;
  for (gint i = 0; i < count; ++i) {
    gchar* name = gdk_atom_name(atoms[i]);
    const bool skip = name == nullptr || IsMetaTarget(name);
    g_free(name);
    if (!skip) job->pending.push_back(atoms[i]);
  }
  if (job->pending.empty()) {
    job->owner->Finish(job, "empty");
    return;
  }
  job->owner->RequestNext(job);
}

void ClipboardSnapshot::RequestNext(const std::shared_ptr<Job>& job) {
  if (job->next >= job->pending.size()) {
    Finish(job, job->got.empty() ? "empty" : "saved");
    return;
  }
  ClipboardReceipt::ScopedSelfRead self_read;
  gtk_clipboard_request_contents(clipboard_, job->pending[job->next],
                                 OnContents, new JobHolder(job));
}

// static
void ClipboardSnapshot::OnContents(GtkClipboard* /*clipboard*/,
                                   GtkSelectionData* data,
                                   gpointer user_data) {
  JobHolder job = TakeHolder(user_data);
  if (job->finished || job->owner == nullptr) return;
  const GdkAtom target = job->pending[job->next];
  ++job->next;
  const gint length = data != nullptr ? gtk_selection_data_get_length(data) : -1;
  if (length >= 0) {
    job->bytes += length;
    if (job->bytes > kSnapshotByteLimit) {
      job->owner->Finish(job, "failed");
      return;
    }
    const guchar* raw = gtk_selection_data_get_data(data);
    job->got.push_back(Target{
        target, gtk_selection_data_get_data_type(data),
        gtk_selection_data_get_format(data),
        std::string(reinterpret_cast<const char*>(raw),
                    static_cast<size_t>(length))});
  }
  job->owner->RequestNext(job);
}

// static
gboolean ClipboardSnapshot::OnTimeout(gpointer user_data) {
  JobHolder job = *static_cast<JobHolder*>(user_data);
  job->timer = 0;
  if (!job->finished && job->owner != nullptr) {
    job->owner->Finish(job, "failed");
  }
  return G_SOURCE_REMOVE;
}

void ClipboardSnapshot::Finish(const std::shared_ptr<Job>& job,
                               const char* status) {
  if (job->finished) return;
  job->finished = true;
  if (job->timer != 0) {
    g_source_remove(job->timer);
    job->timer = 0;
  }
  if (job_ == job) job_.reset();

  Result result;
  result.status = status;
  if (result.status == "saved") {
    for (const Target& target : job->got) {
      if (!result.has_text && IsTextTarget(target.target)) {
        result.text = target.data;
        result.has_text = true;
      }
    }
    result.formats = static_cast<int>(job->got.size());
    result.bytes = job->bytes;
    targets_ = std::move(job->got);
  }
  Done done = std::move(job->done);
  if (done) done(result);
}
