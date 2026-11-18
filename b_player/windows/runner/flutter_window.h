#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Windows accessibility clients (screen readers, IME panels, UIA tools) send
  // WM_GETOBJECT to the Flutter view. Flutter 3.44.8 builds its semantics tree
  // in response and has a known release-only access violation in
  // FlutterPlatformNodeDelegateWindows::HitTestSync
  // (flutter/flutter#195653), which crashed production machines while screen
  // cast panels were being adjusted. We answer MSAA client queries with 0 so
  // the engine never enables semantics; UIA root queries are ignored the same
  // way. Set ENODE_A11Y=1 in the environment to restore the previous
  // behavior for assistive technology users.
  static bool ShouldBlockAccessibility();
  static LRESULT CALLBACK AccessibilityWndProc(HWND hwnd, UINT message,
                                               WPARAM wparam, LPARAM lparam,
                                               UINT_PTR subclass_id,
                                               DWORD_PTR ref_data) noexcept;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
