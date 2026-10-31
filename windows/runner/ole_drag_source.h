// OLE drag-out of one side-panel row (issue 11): the Windows counterpart of
// SidePanelHost.swift's beginNativeDrag.
//
// Text travels as CF_UNICODETEXT. An image (PNG bytes from the clipboard
// history) travels as the registered "PNG" format, which Office, browsers
// and chat apps read, plus CF_DIB for apps that only take bitmaps.

#ifndef RUNNER_OLE_DRAG_SOURCE_H_
#define RUNNER_OLE_DRAG_SOURCE_H_

#include <cstdint>
#include <string>
#include <vector>

namespace OleDragSource {

// Runs a modal OLE drag on the calling (platform) thread until the user
// drops or cancels. Call it only while the left mouse button is held: the
// drag ends at once when it is already up. Returns false when nothing could
// be offered (empty content, undecodable image, OLE unavailable).
bool DragText(const std::wstring& text);
bool DragPng(const std::vector<uint8_t>& png);

}  // namespace OleDragSource

#endif  // RUNNER_OLE_DRAG_SOURCE_H_
