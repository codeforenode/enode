#ifndef FLUTTER_CHROMIUM_WEBVIEW_CEF_RUNTIME_MANAGER_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CEF_RUNTIME_MANAGER_H_

#include <windows.h>
#include <string>
#include <functional>
#include <mutex>
#include <memory>
#include "include/cef_app.h"

// ENODE_CEF_SOFTWARE=1 forces CPU off-screen rendering for A/B comparison.
bool ChromiumSoftwareRendering();

enum class CefRuntimeState {
  kUninitialized,
  kInitializing,
  kReady,
  kShuttingDown,
  kShutdown
};

class CefRuntimeManager {
 public:
  static CefRuntimeManager* GetInstance();

  // Initializes CEF globally. Should only be called once.
  bool Initialize(const std::string& cache_path, int argc, char** argv);
  int ExecuteProcess(void* sandbox_info);
  int initialization_exit_code() const { return initialization_exit_code_; }

  // Shuts down CEF.
  void Shutdown();

  CefRuntimeState GetState() const;
  void BrowserOpened() { ++browser_count_; }
  void BrowserClosed() { --browser_count_; }
  int browser_count() const { return browser_count_; }
  bool pump_running() const { return pump_id_ != 0; }

  // Runs after every CEF message-loop work pass, still on the pumping thread.
  // Used to composite canvas frames strictly outside CEF callbacks.
  void SetPumpHook(std::function<void()> hook);
  void OnPump();

 private:
  CefRuntimeManager();
  ~CefRuntimeManager();

  static CefRuntimeManager* instance_;
  static std::mutex instance_mutex_;

  CefRuntimeState state_;
  std::mutex state_mutex_;
  UINT_PTR pump_id_ = 0;
  int browser_count_ = 0;
  void* sandbox_info_ = nullptr;
  int initialization_exit_code_ = 0;
  std::mutex hook_mutex_;
  std::function<void()> pump_hook_;
};

#endif  // FLUTTER_CHROMIUM_WEBVIEW_CEF_RUNTIME_MANAGER_H_
