#ifndef FLUTTER_CHROMIUM_WEBVIEW_CEF_KEYBOARD_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CEF_KEYBOARD_H_
#include <windows.h>
#include <commctrl.h>
#include "include/cef_browser.h"

// Routes one raw window message (focus, keys, chars, IME) into the given
// browser host. Returns true when the message was consumed and the caller
// must not hand it to the default proc. Shared by the Flutter child HWND
// subclass and the canvas mirror windows, which receive the same messages.
bool SendKeyMessageToCef(CefRefPtr<CefBrowser> browser, HWND window, UINT message,
                         WPARAM wparam, LPARAM lparam);

// Temporary diagnostics for the OSR IME path; appends ASCII lines to
// %TEMP%\enode_ime.log.
void LogImeDebug(const char* format, ...);

// The Flutter child HWND receives native keyboard input.
class CefKeyboard {
 public:
  explicit CefKeyboard(HWND window);
  ~CefKeyboard();
  void SetBrowser(CefRefPtr<CefBrowser> browser);
  bool focused() const { return browser_ != nullptr; }
  bool HasBrowser(CefRefPtr<CefBrowser> browser) const { return browser_ == browser; }
 private:
  static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR);
  HWND window_;
  CefRefPtr<CefBrowser> browser_;
};
#endif
