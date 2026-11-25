#include "system_contacts_host.h"

#include "outlook_contacts_reader.h"

// <unknwn.h> must precede the C++/WinRT headers so `as<>` works.
#include <unknwn.h>

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.ApplicationModel.Contacts.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <cstdint>
#include <cwchar>
#include <functional>
#include <string>
#include <thread>
#include <utility>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::ApplicationModel::Contacts::Contact;
using winrt::Windows::ApplicationModel::Contacts::ContactManager;
using winrt::Windows::ApplicationModel::Contacts::ContactStore;
using winrt::Windows::ApplicationModel::Contacts::ContactStoreAccessType;

using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;

// Private window message carrying a heap-allocated std::function<void()> that
// runs on the platform thread. Distinct from the other runner hosts' messages.
constexpr UINT kPostedWorkMessage = WM_APP + 0x5B;
constexpr char kChannelName[] = "com.whispaste.system_contacts";

// Fallback when Dart sends no limit; mirrors kContactNamesMaxContacts.
constexpr int64_t kDefaultLimit = 5000;

void PostToPlatformThread(HWND window, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(window, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    // Window gone (shutdown): drop the reply, the engine is gone with it.
    delete boxed;
  }
}

// The unpackaged NSIS/ZIP build has no package identity; the MSIX has one
// and declares the `contacts` capability.
bool HasPackageIdentity() {
  UINT32 length = 0;
  return ::GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

EncodableValue Str(const winrt::hstring& value) {
  return EncodableValue(winrt::to_string(value));
}

// Given name with the middle name, as the file sources join them.
winrt::hstring GivenName(const Contact& contact) {
  const winrt::hstring first = contact.FirstName();
  const winrt::hstring middle = contact.MiddleName();
  if (middle.empty()) return first;
  if (first.empty()) return middle;
  return first + L" " + middle;
}

// The first company of the contact's job entries.
winrt::hstring Company(const Contact& contact) {
  for (const auto& job : contact.JobInfo()) {
    const winrt::hstring company = job.CompanyName();
    if (!company.empty()) return company;
  }
  return winrt::hstring();
}

EncodableMap Reply(const char* status, bool packaged) {
  return EncodableMap{
      {EncodableValue("status"), EncodableValue(status)},
      {EncodableValue("packaged"), EncodableValue(packaged)},
  };
}

// Reads the store; runs on a worker thread. Only names and the company
// leave this function. FullName is composed from the name fields; the
// DisplayName is not used, because Windows falls back to an e-mail address
// or phone number there when a contact has no name.
EncodableMap ReadContacts(int64_t limit) {
  const bool packaged = HasPackageIdentity();
  try {
    const ContactStore store =
        ContactManager::RequestStoreAsync(
            ContactStoreAccessType::AllContactsReadOnly)
            .get();
    // No store means the privacy setting refuses access for this app.
    if (!store) return Reply("denied", packaged);
    const auto contacts = store.FindContactsAsync().get();
    if (static_cast<int64_t>(contacts.Size()) > limit) {
      return Reply("tooMany", packaged);
    }
    EncodableList out;
    out.reserve(contacts.Size());
    for (const Contact& contact : contacts) {
      out.emplace_back(EncodableList{
          Str(GivenName(contact)),
          Str(contact.LastName()),
          Str(contact.FullName()),
          Str(Company(contact)),
      });
    }
    EncodableMap reply = Reply("ok", packaged);
    reply[EncodableValue("contacts")] = EncodableValue(std::move(out));
    return reply;
  } catch (const winrt::hresult_error& error) {
    wchar_t code[16];
    swprintf_s(code, L"%08X", static_cast<uint32_t>(error.code()));
    OutputDebugStringW((std::wstring(L"[SystemContacts] Read failed: 0x") +
                        code + L" " + error.message().c_str() + L"\n")
                           .c_str());
    return Reply(error.code() == E_ACCESSDENIED ? "denied" : "unavailable",
                 packaged);
  } catch (...) {
    OutputDebugStringW(L"[SystemContacts] Read failed\n");
    return Reply("unavailable", packaged);
  }
}

int64_t LimitArgument(const EncodableValue* arguments) {
  const auto* map = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
  if (map == nullptr) return kDefaultLimit;
  const auto entry = map->find(EncodableValue("limit"));
  if (entry == map->end()) return kDefaultLimit;
  // Not `small`: <rpcndr.h> defines it as a macro for `char`.
  if (const auto* narrow = std::get_if<int32_t>(&entry->second)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(&entry->second)) return *wide;
  return kDefaultLimit;
}

}  // namespace

SystemContactsHost::SystemContactsHost(flutter::BinaryMessenger* messenger,
                                       HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      window_(window) {
  channel_->SetMethodCallHandler(
      [window](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<Result> raw_result) {
        SharedResult result(std::move(raw_result));
        const bool outlook = call.method_name() == "readOutlook";
        if (call.method_name() != "read" && !outlook) {
          result->NotImplemented();
          return;
        }
        const int64_t limit = LimitArgument(call.arguments());
        std::thread([window, result, limit, outlook] {
          EncodableMap reply;
          try {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            reply = outlook ? ReadOutlookContacts(limit) : ReadContacts(limit);
          } catch (...) {
            // init_apartment itself failed; Dart awaits every call.
            reply = Reply("unavailable", HasPackageIdentity());
          }
          PostToPlatformThread(window, [result, reply] {
            result->Success(EncodableValue(reply));
          });
        }).detach();
      });
}

SystemContactsHost::~SystemContactsHost() {
  channel_->SetMethodCallHandler(nullptr);
}

bool SystemContactsHost::HandleWindowMessage(UINT message, WPARAM,
                                             LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
