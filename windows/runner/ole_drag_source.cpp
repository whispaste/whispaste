#include "ole_drag_source.h"

#include <windows.h>
#include <ole2.h>
#include <shlobj.h>
#include <shlwapi.h>

#include <cstring>

#include "gdiplus_helper.h"

namespace {

// DoDragDrop needs OLE on this thread; main.cpp only sets up COM.
// OleInitialize on an STA that already has COM returns S_OK or S_FALSE. It
// stays initialised for the life of the process, like the platform thread.
bool EnsureOle() {
  static const bool ready = SUCCEEDED(::OleInitialize(nullptr));
  return ready;
}

// Ends the drag on release of the left button, cancels it on Escape.
class DropSource : public IDropSource {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                           void** object) override {
    if (riid == IID_IUnknown || riid == IID_IDropSource) {
      *object = static_cast<IDropSource*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG refs = --refs_;
    if (refs == 0) delete this;
    return refs;
  }
  HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escape_pressed,
                                              DWORD key_state) override {
    if (escape_pressed) return DRAGDROP_S_CANCEL;
    if (!(key_state & MK_LBUTTON)) return DRAGDROP_S_DROP;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override {
    return DRAGDROP_S_USEDEFAULTCURSORS;
  }

 private:
  ULONG refs_ = 1;
};

HGLOBAL CopyToGlobal(const void* data, size_t size) {
  HGLOBAL global = ::GlobalAlloc(GMEM_MOVEABLE, size);
  if (!global) return nullptr;
  void* target = ::GlobalLock(global);
  if (!target) {
    ::GlobalFree(global);
    return nullptr;
  }
  std::memcpy(target, data, size);
  ::GlobalUnlock(global);
  return global;
}

// Hands |global| to |object| (which then owns it); frees it on failure.
bool AddFormat(IDataObject* object, CLIPFORMAT format, HGLOBAL global) {
  if (!global) return false;
  FORMATETC etc = {format, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
  STGMEDIUM medium = {};
  medium.tymed = TYMED_HGLOBAL;
  medium.hGlobal = global;
  if (FAILED(object->SetData(&etc, &medium, TRUE))) {
    ::GlobalFree(global);
    return false;
  }
  return true;
}

// Decodes |png| into a packed bottom-up 32-bit DIB (header + pixels).
HGLOBAL PngToDib(const std::vector<uint8_t>& png) {
  IStream* stream =
      ::SHCreateMemStream(png.data(), static_cast<UINT>(png.size()));
  if (!stream) return nullptr;
  HGLOBAL result = nullptr;
  if (GdiPlusHelper::AddRef()) {
    {
      Gdiplus::Bitmap bitmap(stream);
      const UINT width = bitmap.GetWidth();
      const UINT height = bitmap.GetHeight();
      Gdiplus::Rect rect(0, 0, static_cast<INT>(width),
                         static_cast<INT>(height));
      Gdiplus::BitmapData pixels;
      if (bitmap.GetLastStatus() == Gdiplus::Ok && width > 0 && height > 0 &&
          bitmap.LockBits(&rect, Gdiplus::ImageLockModeRead,
                          PixelFormat32bppARGB, &pixels) == Gdiplus::Ok) {
        const size_t row = static_cast<size_t>(width) * 4;
        const size_t size = sizeof(BITMAPINFOHEADER) + row * height;
        result = ::GlobalAlloc(GMEM_MOVEABLE, size);
        auto* bytes = result ? static_cast<uint8_t*>(::GlobalLock(result))
                             : nullptr;
        if (bytes) {
          auto* header = reinterpret_cast<BITMAPINFOHEADER*>(bytes);
          *header = {};
          header->biSize = sizeof(BITMAPINFOHEADER);
          header->biWidth = static_cast<LONG>(width);
          header->biHeight = static_cast<LONG>(height);  // bottom-up
          header->biPlanes = 1;
          header->biBitCount = 32;
          header->biCompression = BI_RGB;
          header->biSizeImage = static_cast<DWORD>(row * height);
          uint8_t* target = bytes + sizeof(BITMAPINFOHEADER);
          const auto* source = static_cast<const uint8_t*>(pixels.Scan0);
          for (UINT y = 0; y < height; ++y) {
            std::memcpy(target + (height - 1 - y) * row,
                        source + static_cast<size_t>(y) * pixels.Stride, row);
          }
          ::GlobalUnlock(result);
        } else if (result) {
          ::GlobalFree(result);
          result = nullptr;
        }
        bitmap.UnlockBits(&pixels);
      }
    }
    GdiPlusHelper::Release();
  }
  stream->Release();
  return result;
}

IDataObject* NewDataObject() {
  IDataObject* object = nullptr;
  if (FAILED(::SHCreateDataObject(nullptr, 0, nullptr, nullptr,
                                  IID_PPV_ARGS(&object)))) {
    return nullptr;
  }
  return object;
}

bool RunDrag(IDataObject* object) {
  auto* source = new DropSource();
  DWORD effect = DROPEFFECT_NONE;
  const HRESULT hr =
      ::DoDragDrop(object, source, DROPEFFECT_COPY, &effect);
  source->Release();
  object->Release();
  return SUCCEEDED(hr);
}

}  // namespace

namespace OleDragSource {

bool DragText(const std::wstring& text) {
  if (text.empty() || !EnsureOle()) return false;
  IDataObject* object = NewDataObject();
  if (!object) return false;
  const size_t size = (text.size() + 1) * sizeof(wchar_t);
  if (!AddFormat(object, CF_UNICODETEXT, CopyToGlobal(text.c_str(), size))) {
    object->Release();
    return false;
  }
  return RunDrag(object);
}

bool DragPng(const std::vector<uint8_t>& png) {
  if (png.empty() || !EnsureOle()) return false;
  IDataObject* object = NewDataObject();
  if (!object) return false;
  static const CLIPFORMAT png_format =
      static_cast<CLIPFORMAT>(::RegisterClipboardFormatW(L"PNG"));
  const bool has_png =
      AddFormat(object, png_format, CopyToGlobal(png.data(), png.size()));
  const bool has_dib = AddFormat(object, CF_DIB, PngToDib(png));
  if (!has_png && !has_dib) {
    object->Release();
    return false;
  }
  return RunDrag(object);
}

}  // namespace OleDragSource
