// Names from the local classic Outlook (#2039, part of #161): reads the
// default contacts folder of every Outlook store through the Outlook object
// model (COM, late bound) and hands over names and companies only. Never
// Microsoft Graph or an account: only what the running Outlook on this
// computer holds.
//
// Outlook security prompts: the reader touches only members the Outlook
// object model guard does not protect (Session, Stores, GetDefaultFolder,
// Folder.GetTable with the columns MessageClass, FirstName, MiddleName,
// LastName, FullName, CompanyName). No e-mail address, body or recipient is
// read, so Outlook never asks the user to allow access, even with an
// out-of-date virus scanner.
//
// It attaches to a running Outlook only (GetActiveObject) and never starts
// one: a started Outlook may ask for a profile or a password in a dialog
// nobody expects from a dictionary page.
//
// Reply (part of the "readOutlook" method of com.whispaste.system_contacts,
// see system_contacts_host.h):
//   {status, contacts?: [[given, family, full, organization]]}
//   status "ok"           contacts holds every contact (possibly empty)
//          "notInstalled" no classic Outlook registered for COM (none, or
//                         only the new Outlook, which has no COM)
//          "notRunning"   classic Outlook is installed but not open
//          "busy"         Outlook rejected the call (a dialog is open)
//          "tooMany"      more than |limit| contacts
//          "unavailable"  any other failure
//
// Blocks while Outlook answers; call it on a worker thread that has
// initialized COM.
#ifndef RUNNER_OUTLOOK_CONTACTS_READER_H_
#define RUNNER_OUTLOOK_CONTACTS_READER_H_

#include <flutter/encodable_value.h>

#include <cstdint>

flutter::EncodableMap ReadOutlookContacts(int64_t limit);

#endif  // RUNNER_OUTLOOK_CONTACTS_READER_H_
