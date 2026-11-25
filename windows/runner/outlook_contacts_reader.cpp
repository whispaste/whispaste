#include "outlook_contacts_reader.h"

#include <windows.h>
#include <oleauto.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdio>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

// OlDefaultFolders.olFolderContacts.
constexpr int kFolderContacts = 10;

// Table columns, in this order. Every one is free of the object model
// guard; see the header.
constexpr const wchar_t* kColumns[] = {
    L"MessageClass", L"FirstName", L"MiddleName",
    L"LastName",     L"FullName",  L"CompanyName",
};
constexpr LONG kColumnCount = 6;

// A VARIANT that clears itself.
struct Variant {
  VARIANT value;
  Variant() { ::VariantInit(&value); }
  ~Variant() { ::VariantClear(&value); }
  Variant(const Variant&) = delete;
  Variant& operator=(const Variant&) = delete;
};

// A failed step; |code| decides the status the user sees.
struct Failure {
  HRESULT code;
};

VARIANT IntArg(int value) {
  VARIANT v;
  ::VariantInit(&v);
  v.vt = VT_I4;
  v.lVal = value;
  return v;
}

// Calls |name| on |target| (late bound). |args| in reading order; they must
// not own resources (numbers only, or strings the caller frees).
HRESULT Call(IDispatch* target, const wchar_t* name, WORD kind,
             VARIANT* result, std::initializer_list<VARIANT> args = {}) {
  DISPID id = 0;
  LPOLESTR names[] = {const_cast<LPOLESTR>(name)};
  HRESULT hr = target->GetIDsOfNames(IID_NULL, names, 1, LOCALE_USER_DEFAULT,
                                     &id);
  if (FAILED(hr)) return hr;
  // IDispatch takes the arguments last to first.
  std::vector<VARIANT> reversed(args.begin(), args.end());
  std::reverse(reversed.begin(), reversed.end());
  DISPPARAMS params{reversed.empty() ? nullptr : reversed.data(), nullptr,
                    static_cast<UINT>(reversed.size()), 0};
  EXCEPINFO exception{};
  hr = target->Invoke(id, IID_NULL, LOCALE_USER_DEFAULT, kind, &params,
                      result, &exception, nullptr);
  if (hr == DISP_E_EXCEPTION) {
    if (exception.pfnDeferredFillIn) exception.pfnDeferredFillIn(&exception);
    if (FAILED(exception.scode)) hr = exception.scode;
    ::SysFreeString(exception.bstrSource);
    ::SysFreeString(exception.bstrDescription);
    ::SysFreeString(exception.bstrHelpFile);
  }
  return hr;
}

// The object a property or method returns; throws Failure otherwise.
ComPtr<IDispatch> Object(IDispatch* target, const wchar_t* name, WORD kind,
                         std::initializer_list<VARIANT> args = {}) {
  Variant result;
  const HRESULT hr = Call(target, name, kind, &result.value, args);
  if (FAILED(hr)) throw Failure{hr};
  if (result.value.vt != VT_DISPATCH || result.value.pdispVal == nullptr) {
    throw Failure{E_UNEXPECTED};
  }
  ComPtr<IDispatch> out(result.value.pdispVal);
  return out;
}

ComPtr<IDispatch> Get(IDispatch* target, const wchar_t* name,
                      std::initializer_list<VARIANT> args = {}) {
  return Object(target, name, DISPATCH_PROPERTYGET | DISPATCH_METHOD, args);
}

ComPtr<IDispatch> Run(IDispatch* target, const wchar_t* name,
                      std::initializer_list<VARIANT> args = {}) {
  return Object(target, name, DISPATCH_METHOD, args);
}

std::string Utf8(const VARIANT& value) {
  if (value.vt != VT_BSTR || value.bstrVal == nullptr) return std::string();
  const int length = static_cast<int>(::SysStringLen(value.bstrVal));
  if (length == 0) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, value.bstrVal, length,
                                         nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.bstrVal, length, out.data(), size,
                        nullptr, nullptr);
  return out;
}

// Given name with the middle name, as the file sources join them.
std::string JoinGiven(std::string first, const std::string& middle) {
  if (middle.empty()) return first;
  if (first.empty()) return middle;
  return first + " " + middle;
}

// Appends the contacts of |folder| to |out|. Returns false when the folder
// holds more than |limit| contacts in total with what |out| has.
bool ReadFolder(IDispatch* folder, int64_t limit, EncodableList& out) {
  ComPtr<IDispatch> table = Run(folder, L"GetTable");
  ComPtr<IDispatch> columns = Get(table.Get(), L"Columns");
  {
    Variant ignored;
    const HRESULT hr =
        Call(columns.Get(), L"RemoveAll", DISPATCH_METHOD, &ignored.value);
    if (FAILED(hr)) throw Failure{hr};
  }
  for (const wchar_t* name : kColumns) {
    VARIANT arg;
    ::VariantInit(&arg);
    arg.vt = VT_BSTR;
    arg.bstrVal = ::SysAllocString(name);
    Variant ignored;
    const HRESULT hr =
        Call(columns.Get(), L"Add", DISPATCH_METHOD, &ignored.value, {arg});
    ::VariantClear(&arg);
    if (FAILED(hr)) throw Failure{hr};
  }

  // One call for every row: far fewer round trips into Outlook than a
  // GetNextRow per contact. One row more than allowed tells "too many".
  const int64_t room = limit - static_cast<int64_t>(out.size());
  Variant rows;
  const HRESULT hr =
      Call(table.Get(), L"GetArray", DISPATCH_METHOD, &rows.value,
           {IntArg(static_cast<int>(room + 1))});
  if (FAILED(hr)) throw Failure{hr};
  // An empty folder returns no array.
  if (!(rows.value.vt & VT_ARRAY) || rows.value.parray == nullptr) {
    return true;
  }
  SAFEARRAY* array = rows.value.parray;
  if (::SafeArrayGetDim(array) != 2) throw Failure{E_UNEXPECTED};
  LONG low1 = 0, high1 = -1, low2 = 0, high2 = -1;
  ::SafeArrayGetLBound(array, 1, &low1);
  ::SafeArrayGetUBound(array, 1, &high1);
  ::SafeArrayGetLBound(array, 2, &low2);
  ::SafeArrayGetUBound(array, 2, &high2);
  LONG count1 = high1 - low1 + 1;
  LONG count2 = high2 - low2 + 1;
  // Outlook returns array(row, column); SAFEARRAYs keep the left index
  // varying fastest. Should a version return (column, row), the column
  // count tells.
  bool rows_first = true;
  if (count2 != kColumnCount && count1 == kColumnCount) rows_first = false;
  const LONG row_count = rows_first ? count1 : count2;
  if (row_count <= 0) return true;
  if ((rows_first ? count2 : count1) != kColumnCount) {
    throw Failure{E_UNEXPECTED};
  }
  if (static_cast<int64_t>(row_count) > room) return false;
  if ((rows.value.vt & VT_TYPEMASK) != VT_VARIANT) throw Failure{E_UNEXPECTED};

  VARIANT* cells = nullptr;
  if (FAILED(::SafeArrayAccessData(array, reinterpret_cast<void**>(&cells)))) {
    throw Failure{E_UNEXPECTED};
  }
  auto cell = [&](LONG row, LONG column) -> const VARIANT& {
    return rows_first ? cells[row + column * count1]
                      : cells[column + row * count1];
  };
  for (LONG row = 0; row < row_count; ++row) {
    // Contacts only (IPM.Contact and its custom forms); distribution lists
    // (IPM.DistList) hold members, not a name of their own.
    const std::string kind = Utf8(cell(row, 0));
    if (kind.rfind("IPM.Contact", 0) != 0) continue;
    out.emplace_back(EncodableList{
        EncodableValue(JoinGiven(Utf8(cell(row, 1)), Utf8(cell(row, 2)))),
        EncodableValue(Utf8(cell(row, 3))),
        EncodableValue(Utf8(cell(row, 4))),
        EncodableValue(Utf8(cell(row, 5))),
    });
  }
  ::SafeArrayUnaccessData(array);
  return true;
}

EncodableMap Status(const char* status) {
  return EncodableMap{{EncodableValue("status"), EncodableValue(status)}};
}

bool IsBusy(HRESULT code) {
  return code == RPC_E_CALL_REJECTED || code == RPC_E_SERVERCALL_RETRYLATER ||
         code == RPC_E_SERVERCALL_REJECTED;
}

void Log(const wchar_t* what, HRESULT code) {
  wchar_t text[96];
  swprintf_s(text, L"[OutlookContacts] %s: 0x%08X\n", what,
             static_cast<unsigned>(code));
  OutputDebugStringW(text);
}

}  // namespace

EncodableMap ReadOutlookContacts(int64_t limit) {
  CLSID clsid;
  if (FAILED(::CLSIDFromProgID(L"Outlook.Application", &clsid))) {
    return Status("notInstalled");
  }
  ComPtr<IUnknown> running;
  // MK_E_UNAVAILABLE when no Outlook runs; also when it runs at another
  // integrity level, which looks the same to the user.
  const HRESULT attach = ::GetActiveObject(clsid, nullptr, &running);
  if (FAILED(attach) || !running) {
    Log(L"Not running", attach);
    return Status("notRunning");
  }
  try {
    ComPtr<IDispatch> app;
    const HRESULT cast = running.As(&app);
    if (FAILED(cast)) throw Failure{cast};
    ComPtr<IDispatch> session = Get(app.Get(), L"Session");
    EncodableList out;
    bool any_folder = false;

    // The default contacts folder of every store (a PST, each account).
    ComPtr<IDispatch> stores = Get(session.Get(), L"Stores");
    Variant count;
    if (SUCCEEDED(Call(stores.Get(), L"Count", DISPATCH_PROPERTYGET,
                       &count.value)) &&
        SUCCEEDED(::VariantChangeType(&count.value, &count.value, 0, VT_I4))) {
      for (int i = 1; i <= count.value.lVal; ++i) {
        ComPtr<IDispatch> folder;
        try {
          ComPtr<IDispatch> store = Get(stores.Get(), L"Item", {IntArg(i)});
          folder = Run(store.Get(), L"GetDefaultFolder",
                       {IntArg(kFolderContacts)});
        } catch (const Failure& failure) {
          // A store without contacts (public folders, an archive) is
          // skipped; a busy Outlook is not.
          if (IsBusy(failure.code)) throw;
          continue;
        }
        any_folder = true;
        if (!ReadFolder(folder.Get(), limit, out)) return Status("tooMany");
      }
    }
    if (!any_folder) {
      ComPtr<IDispatch> folder =
          Run(session.Get(), L"GetDefaultFolder", {IntArg(kFolderContacts)});
      if (!ReadFolder(folder.Get(), limit, out)) return Status("tooMany");
    }
    EncodableMap reply = Status("ok");
    reply[EncodableValue("contacts")] = EncodableValue(std::move(out));
    return reply;
  } catch (const Failure& failure) {
    Log(L"Read failed", failure.code);
    return Status(IsBusy(failure.code) ? "busy" : "unavailable");
  }
}
