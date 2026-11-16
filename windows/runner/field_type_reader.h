// Reads the type of the focused field of another app through UI Automation
// (#948): a password or PIN field, a normal text field, or unknown. Flutter-free
// so it stays testable on its own and FieldTypeHost only wires the channel.
//
// Privacy: only the IsPassword property and the presence of the Text or Value
// pattern are read, never the field's text, value or name.

#ifndef RUNNER_FIELD_TYPE_READER_H_
#define RUNNER_FIELD_TYPE_READER_H_

#include <string>

namespace field_type {

// Blocking; call it on a worker thread. Initialises COM (MTA) for the calling
// thread itself. UIA connection and transaction timeouts bound a hung target.
// Returns "password", "normal" or "unknown". WhisPaste's own windows, a missing
// focus, an error and a field without proof of being a text field are
// "unknown".
std::string Read();

}  // namespace field_type

#endif  // RUNNER_FIELD_TYPE_READER_H_
