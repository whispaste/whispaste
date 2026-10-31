#include "support_store_channel.h"

// <unknwn.h> must precede the C++/WinRT headers so `as<>` works with the
// classic COM interface IInitializeWithWindow.
#include <unknwn.h>

#include <appmodel.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>
#include <shobjidl_core.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Services.Store.h>

#include <cstdint>
#include <exception>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Services::Store::StoreAppLicense;
using winrt::Windows::Services::Store::StoreConsumableStatus;
using winrt::Windows::Services::Store::StoreContext;
using winrt::Windows::Services::Store::StoreProduct;
using winrt::Windows::Services::Store::StoreProductQueryResult;
using winrt::Windows::Services::Store::StorePurchaseResult;
using winrt::Windows::Services::Store::StorePurchaseStatus;

using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;
// Receives the final purchase status name; always invoked on the platform thread.
using Finish = std::function<void(std::string)>;

// Private window message carrying a heap-allocated std::function<void()> that
// runs on the platform thread. Distinct from the other runner hosts' messages.
constexpr UINT kPostedWorkMessage = WM_APP + 0x52;

constexpr char kChannelName[] = "com.whispaste.support_store";

// Product kinds of the sponsoring catalogue. Partner Center's "Developer-
// managed" consumables are UnmanagedConsumable.
winrt::Windows::Foundation::Collections::IVector<winrt::hstring> ProductKinds() {
  return winrt::single_threaded_vector<winrt::hstring>(
      {L"Durable", L"Consumable", L"UnmanagedConsumable"});
}

// Store APIs need a package identity; an unpackaged `flutter run` build has
// none and every Store call would fail with an opaque HRESULT.
bool HasPackageIdentity() {
  UINT32 length = 0;
  return ::GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

// One context for the app's lifetime; the purchase dialog needs the owner
// window (desktop apps have no CoreWindow). Throws winrt::hresult_error.
StoreContext Context(HWND window) {
  static StoreContext context = [window] {
    StoreContext created = StoreContext::GetDefault();
    created.as<IInitializeWithWindow>()->Initialize(window);
    return created;
  }();
  return context;
}

// The Store context, or nullopt when the process is not packaged or the Store
// cannot be reached. Never throws.
std::optional<StoreContext> TryContext(HWND window) {
  if (!HasPackageIdentity()) return std::nullopt;
  try {
    return Context(window);
  } catch (...) {
    return std::nullopt;
  }
}

// Posts |work| to the platform thread (the runner window's message loop).
void PostToPlatformThread(HWND window, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(window, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    // The window is gone (shutdown): the engine that awaited the reply is
    // gone with it, and a reply from this thread would be unsafe.
    delete boxed;
    OutputDebugStringW(L"[SupportStore] Reply dropped: window gone\n");
  }
}

std::string HresultMessage(const winrt::hresult_error& error) {
  return winrt::to_string(error.message()) + " (0x" +
         std::to_string(static_cast<uint32_t>(error.code())) + ")";
}

EncodableValue Str(const winrt::hstring& value) {
  return EncodableValue(winrt::to_string(value));
}

void CheckQuery(const StoreProductQueryResult& query) {
  if (query.ExtendedError() != winrt::hresult{}) {
    throw winrt::hresult_error(query.ExtendedError());
  }
}

// The Store offer whose InAppOfferToken is |offer_id|, if the catalogue has it.
std::optional<StoreProduct> FindOffer(const StoreProductQueryResult& query,
                                      const std::string& offer_id) {
  for (const auto& entry : query.Products()) {
    const StoreProduct product = entry.Value();
    if (winrt::to_string(product.InAppOfferToken()) == offer_id) {
      return product;
    }
  }
  return std::nullopt;
}

// Offers in the requested order; ids the catalogue lacks are skipped.
EncodableValue Offers(const StoreProductQueryResult& query,
                      const std::vector<std::string>& offer_ids) {
  CheckQuery(query);
  EncodableList offers;
  for (const auto& offer_id : offer_ids) {
    const auto product = FindOffer(query, offer_id);
    if (!product) continue;
    offers.emplace_back(EncodableMap{
        {EncodableValue("productId"), EncodableValue(offer_id)},
        {EncodableValue("title"), Str(product->Title())},
        {EncodableValue("formattedPrice"),
         Str(product->Price().FormattedPrice())},
    });
  }
  return EncodableValue(offers);
}

// Completes |operation| on a thread-pool thread and runs |on_done| with its
// results there, or |on_fail| with a message when Store reports an error. Any
// work |on_done| needs on the platform thread must go through
// PostToPlatformThread.
template <typename Operation, typename OnDone, typename OnFail>
void OnStoreCompleted(Operation operation, OnDone on_done, OnFail on_fail) {
  operation.Completed([on_done, on_fail](const auto& sender,
                                         AsyncStatus status) {
    try {
      if (status != AsyncStatus::Completed) {
        throw winrt::hresult_error(sender.ErrorCode());
      }
      on_done(sender.GetResults());
    } catch (const winrt::hresult_error& error) {
      on_fail(HresultMessage(error));
    } catch (...) {
      on_fail("Unexpected Store failure.");
    }
  });
}

// Replies to |reply| with |convert|(results) on the platform thread, or with
// the "store_error" error when Store fails.
template <typename Operation, typename Convert>
void ReplyWhenDone(HWND window, SharedResult reply, Operation operation,
                   Convert convert) {
  OnStoreCompleted(
      operation,
      [window, reply, convert](const auto& results) {
        const EncodableValue value = convert(results);
        PostToPlatformThread(window,
                             [reply, value] { reply->Success(value); });
      },
      [window, reply](const std::string& message) {
        PostToPlatformThread(window, [reply, message] {
          reply->Error("store_error", message);
        });
      });
}

std::string PurchaseStatusName(StorePurchaseStatus status) {
  switch (status) {
    case StorePurchaseStatus::NotPurchased:
      return "cancelled";
    case StorePurchaseStatus::NetworkError:
      return "networkError";
    default:
      return "serverError";
  }
}

// Fulfils a developer-managed consumable (quantity is always 1). Must run on the platform thread, like every
// call on the StoreContext. An unfulfilled purchase is re-delivered by the
// Store as AlreadyPurchased on the next purchase attempt.
void Fulfil(const StoreContext& context, const winrt::hstring& store_id,
            const Finish& finish) {
  GUID tracking_id{};
  ::CoCreateGuid(&tracking_id);
  OnStoreCompleted(
      context.ReportConsumableFulfillmentAsync(store_id, 1,
                                               winrt::guid{tracking_id}),
      [finish](const auto& result) {
        finish(result.Status() == StoreConsumableStatus::Succeeded
                   ? "succeeded"
                   : "serverError");
      },
      [finish](const std::string&) { finish("serverError"); });
}

// Starts the purchase dialog. Must run on the platform thread, because the
// dialog is modal to the runner window.
void StartPurchase(HWND window, const StoreContext& context,
                   const winrt::hstring& store_id, const Finish& finish) {
  OnStoreCompleted(
      context.RequestPurchaseAsync(store_id),
      [window, context, store_id, finish](const StorePurchaseResult& purchase) {
        const StorePurchaseStatus status = purchase.Status();
        // AlreadyPurchased is an unfulfilled earlier payment, so it still
        // needs fulfilment before it counts as support.
        if (status == StorePurchaseStatus::Succeeded ||
            status == StorePurchaseStatus::AlreadyPurchased) {
          PostToPlatformThread(window, [context, store_id, finish] {
            Fulfil(context, store_id, finish);
          });
        } else {
          finish(PurchaseStatusName(status));
        }
      },
      [finish](const std::string&) { finish("serverError"); });
}

// Resolves the Store id for |offer_id| (thread pool), then starts the purchase
// on the platform thread. Always answers with a status name.
void Purchase(HWND window, const SharedResult& reply,
              const StoreContext& context, const std::string& offer_id) {
  const Finish finish = [window, reply](std::string status) {
    PostToPlatformThread(window, [reply, status] {
      reply->Success(EncodableValue(status));
    });
  };
  OnStoreCompleted(
      context.GetAssociatedStoreProductsAsync(ProductKinds()),
      [window, context, offer_id, finish](const StoreProductQueryResult& query) {
        CheckQuery(query);
        const auto product = FindOffer(query, offer_id);
        if (!product) {
          finish("unavailable");
          return;
        }
        const winrt::hstring store_id = product->StoreId();
        PostToPlatformThread(window, [window, context, store_id, finish] {
          StartPurchase(window, context, store_id, finish);
        });
      },
      [finish](const std::string&) { finish("serverError"); });
}

const EncodableValue* ArgumentValue(const flutter::MethodCall<EncodableValue>& call,
                                    const char* key) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr) return nullptr;
  const auto entry = args->find(EncodableValue(key));
  return entry == args->end() ? nullptr : &entry->second;
}

std::optional<std::string> StringArgument(
    const flutter::MethodCall<EncodableValue>& call, const char* key) {
  const EncodableValue* value = ArgumentValue(call, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  if (text == nullptr) return std::nullopt;
  return *text;
}

std::optional<std::vector<std::string>> StringListArgument(
    const flutter::MethodCall<EncodableValue>& call, const char* key) {
  const EncodableValue* value = ArgumentValue(call, key);
  const auto* list = value ? std::get_if<EncodableList>(value) : nullptr;
  if (list == nullptr) return std::nullopt;
  std::vector<std::string> ids;
  for (const auto& item : *list) {
    const auto* text = std::get_if<std::string>(&item);
    if (text == nullptr) return std::nullopt;
    ids.push_back(*text);
  }
  return ids;
}

void HandleMethodCall(HWND window, const flutter::MethodCall<EncodableValue>& call,
                      const SharedResult& reply) {
  const std::string& method = call.method_name();
  try {
    if (method == "isAvailable") {
      reply->Success(EncodableValue(TryContext(window).has_value()));
      return;
    }

    if (method == "loadProducts") {
      const auto offer_ids = StringListArgument(call, "productIds");
      if (!offer_ids) {
        reply->Error("bad_args", "loadProducts needs a productIds list.");
        return;
      }
      const auto context = TryContext(window);
      if (!context) {
        reply->Success(EncodableValue(EncodableList{}));
        return;
      }
      ReplyWhenDone(window, reply,
                    context->GetAssociatedStoreProductsAsync(ProductKinds()),
                    [ids = *offer_ids](const StoreProductQueryResult& query) {
                      return Offers(query, ids);
                    });
      return;
    }

    if (method == "purchase") {
      const auto offer_id = StringArgument(call, "productId");
      if (!offer_id) {
        reply->Error("bad_args", "purchase needs a productId.");
        return;
      }
      const auto context = TryContext(window);
      if (!context) {
        reply->Success(EncodableValue("unavailable"));
        return;
      }
      Purchase(window, reply, *context, *offer_id);
      return;
    }

    if (method == "hasVerifiedAppPurchase") {
      const auto context = TryContext(window);
      if (!context) {
        reply->Success(EncodableValue(false));
        return;
      }
      ReplyWhenDone(window, reply, context->GetAppLicenseAsync(),
                    [](const StoreAppLicense& license) {
                      return EncodableValue(license.IsActive() &&
                                            !license.IsTrial());
                    });
      return;
    }

    reply->NotImplemented();
  } catch (const winrt::hresult_error& error) {
    reply->Error("store_error", HresultMessage(error));
  } catch (const std::exception& error) {
    // Argument decoding or a container can throw too; Dart awaits every call,
    // so each one must end in a reply.
    reply->Error("store_error", error.what());
  } catch (...) {
    reply->Error("store_error", "Unexpected Store failure.");
  }
}

}  // namespace

SupportStoreChannel::SupportStoreChannel(flutter::BinaryMessenger* messenger,
                                         HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      window_(window) {
  channel_->SetMethodCallHandler([window = window_](const auto& call,
                                                    auto result) {
    HandleMethodCall(window, call, SharedResult(std::move(result)));
  });
}

SupportStoreChannel::~SupportStoreChannel() {
  channel_->SetMethodCallHandler(nullptr);
}

bool SupportStoreChannel::HandleWindowMessage(UINT message, WPARAM, LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
