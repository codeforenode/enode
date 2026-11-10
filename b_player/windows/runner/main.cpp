#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include <flutter_chromium_webview/flutter_chromium_webview_plugin_c_api.h>

// CEF 的 Windows 沙箱不允许普通 exe 自己当宿主：eNode.exe 是厂商 bootstrap，
// 它加载同名 eNode.dll 后进这个导出函数。子进程（CEF 渲染/工具进程）走同一条入口，
// ExecuteProcess 返回 >=0 就直接退出，不会碰到 Flutter 与 Dart。
extern "C" __declspec(dllexport) int RunWinMain(
    HINSTANCE instance, wchar_t* command_line, int show_command,
    void* sandbox_info, void* version_info) {
  (void)instance;
  (void)command_line;
  (void)show_command;
  (void)version_info;
  const int cef_exit = FlutterChromiumWebviewExecuteProcess(sandbox_info);
  if (cef_exit >= 0) return cef_exit;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"eNode", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
