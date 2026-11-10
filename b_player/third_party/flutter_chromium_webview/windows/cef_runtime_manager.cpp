#include "include/cef_runtime_manager.h"
#include <iostream>
#include <filesystem>
#include "../native/javascript_bridge.h"

bool ChromiumSoftwareRendering() {
  char value[8] = {};
  const DWORD length = GetEnvironmentVariableA("ENODE_CEF_SOFTWARE", value, sizeof(value));
  return length > 0 && length < sizeof(value) && value[0] == '1';
}

namespace {

class RenderingApp : public CefApp {
 public:
  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                    CefRefPtr<CefCommandLine> command_line) override {
    if (!ChromiumSoftwareRendering()) return;
    command_line->AppendSwitch("disable-gpu");
    command_line->AppendSwitch("disable-gpu-compositing");
  }
 private:
  IMPLEMENT_REFCOUNTING(RenderingApp);
};

VOID CALLBACK PumpCallback(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
  // A Win32 timer can also fire from a nested loop (modal move/size, popup
  // menu). Re-entering CEF from inside its own work corrupts its observer
  // lists, so let the outer pass finish this tick.
  static thread_local bool pumping = false;
  if (pumping) return;
  pumping = true;
  CefDoMessageLoopWork();
  pumping = false;
  CefRuntimeManager::GetInstance()->OnPump();
}

}  // namespace

CefRuntimeManager* CefRuntimeManager::instance_ = nullptr;
std::mutex CefRuntimeManager::instance_mutex_;

CefRuntimeManager::CefRuntimeManager() : state_(CefRuntimeState::kUninitialized) {}

CefRuntimeManager::~CefRuntimeManager() {}

CefRuntimeManager* CefRuntimeManager::GetInstance() {
  std::lock_guard<std::mutex> lock(instance_mutex_);
  if (!instance_) {
    instance_ = new CefRuntimeManager();
  }
  return instance_;
}

int CefRuntimeManager::ExecuteProcess(void* sandbox_info) {
  if (!sandbox_info) return ERROR_INVALID_PARAMETER;
  sandbox_info_ = sandbox_info;
  return CefExecuteProcess(CefMainArgs(GetModuleHandleW(nullptr)), new chromium_bridge::RendererApp(), sandbox_info);
}

bool CefRuntimeManager::Initialize(const std::string& cache_path, int argc, char** argv) {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (state_ != CefRuntimeState::kUninitialized) {
    return state_ == CefRuntimeState::kReady;
  }
  if (!sandbox_info_) {
    std::cerr << "[CEF] Sandboxed Windows startup requires the CEF bootstrap runner" << std::endl;
    initialization_exit_code_ = ERROR_INVALID_PARAMETER;
    return false;
  }
  
  state_ = CefRuntimeState::kInitializing;

  HINSTANCE hInstance = GetModuleHandle(nullptr);
  CefMainArgs main_args(hInstance);
  CefSettings settings;

  // Keep Chromium's sandbox enabled. Unsupported hosts must fail explicitly;
  // no automatic --no-sandbox fallback is permitted.
  settings.windowless_rendering_enabled = true;

  // Set paths
  CefString(&settings.cache_path) = cache_path;
  CefString(&settings.root_cache_path) = cache_path;

  // The subprocess path
  wchar_t exe_path[32768] = {};
  const DWORD length = GetModuleFileNameW(nullptr, exe_path, 32768);
  if (!length || length == 32768) {
    state_ = CefRuntimeState::kUninitialized;
    return false;
  }
  const auto dir = std::filesystem::path(exe_path).parent_path();
  // Sandboxed processes must use this same bootstrap executable.

  // CEF resources are in the same dir when bundled in Flutter Windows
  CefString(&settings.resources_dir_path) = dir.wstring();
  CefString(&settings.locales_dir_path) = dir.wstring();
  CefString(&settings.log_file) = cache_path + "/cef.log";

  // Initialize CEF
  std::cerr << "[CEF] Initializing runtime" << std::endl;
  bool success = CefInitialize(main_args, settings, new RenderingApp(), sandbox_info_);
  initialization_exit_code_ = CefGetExitCode();
  std::cerr << "[CEF] Initialization result: " << success
            << "; exit code: " << initialization_exit_code_ << std::endl;
  
  if (success) {
    state_ = CefRuntimeState::kReady;
    pump_id_ = SetTimer(nullptr, 0, 10, PumpCallback);
  } else {
    // CEF initialization is a one-shot operation, including early exits.
    state_ = CefRuntimeState::kShutdown;
  }
  
  return success;
}

void CefRuntimeManager::Shutdown() {
  std::lock_guard<std::mutex> lock(state_mutex_);
  if (state_ != CefRuntimeState::kReady) {
    return;
  }

  state_ = CefRuntimeState::kShuttingDown;
  if (pump_id_) {
    KillTimer(nullptr, pump_id_);
    pump_id_ = 0;
  }
  // Plugin shutdown handlers request closure before this after-handler runs.
  // Continue CEF work until all CloseBrowser requests have been acknowledged.
  ULONGLONG deadline = GetTickCount64() + 5000;
  while (browser_count_ > 0 && GetTickCount64() < deadline) {
    CefDoMessageLoopWork();
    Sleep(1);
  }
  if (browser_count_ != 0) {
    std::cerr << "[CEF] Shutdown timed out with " << browser_count_ << " browsers; skipping unsafe CefShutdown" << std::endl;
    return;
  }
  CefShutdown();
  state_ = CefRuntimeState::kShutdown;
  std::cerr << "[CEF] Shutdown complete" << std::endl;
}

CefRuntimeState CefRuntimeManager::GetState() const {
  return state_;
}

void CefRuntimeManager::SetPumpHook(std::function<void()> hook) {
  std::lock_guard<std::mutex> lock(hook_mutex_);
  pump_hook_ = std::move(hook);
}

void CefRuntimeManager::OnPump() {
  std::function<void()> hook;
  {
    std::lock_guard<std::mutex> lock(hook_mutex_);
    hook = pump_hook_;
  }
  if (hook) hook();
}
