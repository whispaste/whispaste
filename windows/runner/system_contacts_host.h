// Names from the Windows contacts (#2038, part of #161): reads the system
// contact store (Windows.ApplicationModel.Contacts, the People store) read-
// only and hands over names and companies only, never addresses, phone
// numbers or e-mail addresses. Called from the dictionary's contact page
// only, never on the hotkey path.
//
// Channel "com.whispaste.system_contacts" (contract mirrored in
// lib/services/dictionary/windows_contact_source.dart):
//   read {limit: int} -> {status, packaged: bool, contacts?: [[given, family,
//                         full, organization]]}
//     status "ok"          contacts holds every contact (possibly empty)
//            "denied"      the privacy setting "Contacts" refuses access
//                          (RequestStoreAsync gave no store or
//                          E_ACCESSDENIED)
//            "unavailable" the API failed otherwise (no store, an
//                          unpackaged build without identity, an old system)
//            "tooMany"     more than |limit| contacts
//   packaged tells whether the process has a package identity (MSIX); the
//   unpackaged NSIS/ZIP build has none, which limits what Windows allows.
//   readOutlook {limit: int} -> {status, contacts?: [...]}
//     the local classic Outlook (#2039), same contact lists; statuses in
//     outlook_contacts_reader.h. Works in every build, packaged or not.
//
// The store blocks while it reads, so every call runs on its own worker
// thread (MTA) and the reply is posted back to the platform thread.
#ifndef RUNNER_SYSTEM_CONTACTS_HOST_H_
#define RUNNER_SYSTEM_CONTACTS_HOST_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class SystemContactsHost {
 public:
  SystemContactsHost(flutter::BinaryMessenger* messenger, HWND window);
  ~SystemContactsHost();

  SystemContactsHost(const SystemContactsHost&) = delete;
  SystemContactsHost& operator=(const SystemContactsHost&) = delete;

  // Runs a reply posted by a worker thread. Returns true when |message| was
  // such a reply (the caller then stops processing it).
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
};

#endif  // RUNNER_SYSTEM_CONTACTS_HOST_H_
