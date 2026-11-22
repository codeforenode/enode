#include "include/canvas_presenter.h"

#include <d3dcompiler.h>
#include <dwmapi.h>
#include <imm.h>

#include <algorithm>
#include <iostream>
#include <new>
#include <thread>

#include "include/cef_keyboard.h"

namespace {

// Every live set, so the CEF pump tick can flush whatever the paint callback
// queued. Guards construction/destruction against the pump's traversal.
std::mutex g_live_sets_mutex;
std::vector<CanvasPresenterSet*> g_live_sets;

constexpr wchar_t kPresenterClass[] = L"EnodeCanvasPresenter";
constexpr wchar_t kMenuOwnerClass[] = L"EnodePresenterMenu";
constexpr UINT kPresenterMenuMessage = WM_APP + 57;

// Menu labels are \u escapes so this file stays pure ASCII for MSVC.
constexpr wchar_t kCloseScreen[] = L"\u5173\u95ED\u672C\u5C4F\u6295\u653E";
constexpr wchar_t kCloseAll[] = L"\u5173\u95ED\u5168\u90E8\u6295\u653E";
constexpr wchar_t kCloseCast[] = L"\u5173\u95ED\u6295\u653E";

struct PresenterBinding {
  CanvasPresenterSet* owner;
  int index;
};

LRESULT CALLBACK MenuOwnerProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void EnsureMenuOwnerClass() {
  static std::once_flag once;
  std::call_once(once, [] {
    WNDCLASSEXW wc = {sizeof(WNDCLASSEXW)};
    wc.lpfnWndProc = MenuOwnerProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kMenuOwnerClass;
    RegisterClassExW(&wc);
  });
}

// TrackPopupMenu runs a modal loop that starves this thread's timers, and the
// CEF pump lives on this thread. Show the menu from a throwaway thread so the
// canvas keeps presenting while the operator is choosing.
void ShowPresenterMenu(HWND presenter, int screens) {
  POINT cursor{};
  if (!GetCursorPos(&cursor)) return;
  std::thread([presenter, screens, cursor] {
    EnsureMenuOwnerClass();
    HWND owner = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED,
                                 kMenuOwnerClass, L"", WS_POPUP, cursor.x, cursor.y, 1, 1,
                                 nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (!owner) return;
    SetLayeredWindowAttributes(owner, 0, 0, LWA_ALPHA);
    ShowWindow(owner, SW_SHOWNA);
    HMENU menu = CreatePopupMenu();
    if (!menu) {
      DestroyWindow(owner);
      return;
    }
    if (screens > 1) {
      AppendMenuW(menu, MF_STRING, CanvasPresenterSet::kMenuCloseScreen, kCloseScreen);
      AppendMenuW(menu, MF_STRING, CanvasPresenterSet::kMenuCloseAll, kCloseAll);
    } else {
      AppendMenuW(menu, MF_STRING, CanvasPresenterSet::kMenuCloseScreen, kCloseCast);
    }
    // Without a foreground owner the menu ignores clicks outside of it.
    SetForegroundWindow(owner);
    const UINT command = TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_RETURNCMD,
                                        cursor.x, cursor.y, 0, owner, nullptr);
    PostMessageW(owner, WM_NULL, 0, 0);
    DestroyMenu(menu);
    DestroyWindow(owner);
    if (command) PostMessageW(presenter, kPresenterMenuMessage, command, 0);
  }).detach();
}

constexpr char kShaderSource[] = R"(
struct VSOut {
  float4 pos : SV_Position;
  float2 uv : TEXCOORD0;
};

VSOut VSMain(uint id : SV_VertexID) {
  VSOut o;
  o.uv = float2((id << 1) & 2, id & 2);
  o.pos = float4(o.uv.x * 2.0 - 1.0, 1.0 - o.uv.y * 2.0, 0.0, 1.0);
  return o;
}

cbuffer Crop : register(b0) {
  float4 uv_rect;
};

Texture2D canvas_texture : register(t0);
SamplerState canvas_sampler : register(s0);

float4 PSMain(VSOut i) : SV_Target {
  return canvas_texture.Sample(canvas_sampler, uv_rect.xy + i.uv * uv_rect.zw);
}
)";

LRESULT CALLBACK PresenterProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* binding = reinterpret_cast<PresenterBinding*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_NCHITTEST:
      // Let clicks fall through to whatever is under the presentation window,
      // except while the right button is down: the system hit-tests again for
      // every button message, so this leaves the right-click gesture to us.
      if (GetAsyncKeyState(VK_RBUTTON) & 0x8000) return HTCLIENT;
      return HTTRANSPARENT;
    case WM_RBUTTONDOWN:
      SetCapture(hwnd);
      return 0;
    case WM_RBUTTONUP:
      if (GetCapture() == hwnd) ReleaseCapture();
      if (binding) ShowPresenterMenu(hwnd, binding->owner ? static_cast<int>(binding->owner->count()) : 1);
      return 0;
    case WM_CAPTURECHANGED:
      return 0;
    case kPresenterMenuMessage:
      if (binding && binding->owner) {
        binding->owner->NotifyMenu(binding->index, static_cast<int>(wparam));
      }
      return 0;
    case WM_NCDESTROY:
      delete binding;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

void EnsureWindowClass() {
  static std::once_flag once;
  std::call_once(once, [] {
    WNDCLASSEXW wc = {sizeof(WNDCLASSEXW)};
    wc.lpfnWndProc = PresenterProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kPresenterClass;
    RegisterClassExW(&wc);
  });
}

}  // namespace

CanvasPresenterSet::CanvasPresenterSet(ID3D11Device* device)
    : device_(device), context_(nullptr) {
  if (device_) device_->GetImmediateContext(&context_);
  std::lock_guard<std::mutex> lock(g_live_sets_mutex);
  g_live_sets.push_back(this);
}

CanvasPresenterSet::~CanvasPresenterSet() {
  Clear();
  std::lock_guard<std::mutex> lock(g_live_sets_mutex);
  g_live_sets.erase(std::remove(g_live_sets.begin(), g_live_sets.end(), this),
                    g_live_sets.end());
}

bool CanvasPresenterSet::Initialize() {
  if (!device_ || !context_) return false;
  Microsoft::WRL::ComPtr<ID3DBlob> vertex_blob;
  Microsoft::WRL::ComPtr<ID3DBlob> pixel_blob;
  Microsoft::WRL::ComPtr<ID3DBlob> error;
  HRESULT hr = D3DCompile(kShaderSource, sizeof(kShaderSource) - 1, nullptr, nullptr, nullptr,
                          "VSMain", "vs_4_0", 0, 0, &vertex_blob, &error);
  if (FAILED(hr)) {
    std::cerr << "[Canvas] vertex shader failed: "
              << (error ? static_cast<const char*>(error->GetBufferPointer()) : "?") << std::endl;
    return false;
  }
  hr = D3DCompile(kShaderSource, sizeof(kShaderSource) - 1, nullptr, nullptr, nullptr,
                  "PSMain", "ps_4_0", 0, 0, &pixel_blob, &error);
  if (FAILED(hr)) {
    std::cerr << "[Canvas] pixel shader failed: "
              << (error ? static_cast<const char*>(error->GetBufferPointer()) : "?") << std::endl;
    return false;
  }
  if (FAILED(device_->CreateVertexShader(vertex_blob->GetBufferPointer(),
                                         vertex_blob->GetBufferSize(), nullptr, &vertex_shader_)) ||
      FAILED(device_->CreatePixelShader(pixel_blob->GetBufferPointer(),
                                        pixel_blob->GetBufferSize(), nullptr, &pixel_shader_))) {
    return false;
  }

  D3D11_SAMPLER_DESC sampler_desc{};
  sampler_desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  sampler_desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.ComparisonFunc = D3D11_COMPARISON_NEVER;
  sampler_desc.MaxLOD = D3D11_FLOAT32_MAX;
  if (FAILED(device_->CreateSamplerState(&sampler_desc, &sampler_))) return false;

  D3D11_BUFFER_DESC buffer_desc{};
  buffer_desc.ByteWidth = 16;
  buffer_desc.Usage = D3D11_USAGE_DEFAULT;
  buffer_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  if (FAILED(device_->CreateBuffer(&buffer_desc, nullptr, &crop_buffer_))) return false;

  D3D11_RASTERIZER_DESC rasterizer_desc{};
  rasterizer_desc.FillMode = D3D11_FILL_SOLID;
  rasterizer_desc.CullMode = D3D11_CULL_NONE;
  rasterizer_desc.DepthClipEnable = TRUE;
  if (FAILED(device_->CreateRasterizerState(&rasterizer_desc, &rasterizer_))) return false;

  // DirectComposition lets a popup window blend per-pixel alpha with the
  // desktop. Without it we keep the old opaque HWND swapchain so casting still
  // works on machines where composition is unavailable.
  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  if (SUCCEEDED(device_->QueryInterface(IID_PPV_ARGS(&dxgi_device)))) {
    if (FAILED(DCompositionCreateDevice(dxgi_device.Get(), IID_PPV_ARGS(&dcomp_)))) {
      std::cerr << "[Canvas] DirectComposition unavailable; presenters stay opaque" << std::endl;
      dcomp_.Reset();
    }
  }
  return true;
}

bool CanvasPresenterSet::Add(int left, int top, int width, int height,
                             float u0, float v0, float u1, float v1) {
  if (!device_ || width <= 0 || height <= 0) return false;
  EnsureWindowClass();

  // A composition target needs a window without a redirection bitmap; otherwise
  // DWM would also draw the (empty) GDI surface behind our visual.
  const bool composed = dcomp_ != nullptr;
  HWND hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          (composed ? WS_EX_NOREDIRECTIONBITMAP : 0),
      kPresenterClass, L"eNode canvas", WS_POPUP, left, top, width, height, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (!hwnd) {
    std::cerr << "[Canvas] CreateWindowEx failed: " << GetLastError() << std::endl;
    return false;
  }
  auto* binding = new (std::nothrow) PresenterBinding{
      this, static_cast<int>(presenters_.size())};
  if (!binding) {
    DestroyWindow(hwnd);
    return false;
  }
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(binding));

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  Microsoft::WRL::ComPtr<IDXGIFactory2> factory;
  if (FAILED(device_->QueryInterface(IID_PPV_ARGS(&dxgi_device))) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->GetParent(IID_PPV_ARGS(&factory)))) {
    DestroyWindow(hwnd);
    return false;
  }

  DXGI_SWAP_CHAIN_DESC1 desc{};
  desc.Width = static_cast<UINT>(width);
  desc.Height = static_cast<UINT>(height);
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  desc.BufferCount = 2;
  desc.Scaling = DXGI_SCALING_STRETCH;
  desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  // The canvas texture is premultiplied BGRA (Chromium's compositor output), so
  // the presenter blends it that way too; opaque pixels look exactly as before.
  desc.AlphaMode = composed ? DXGI_ALPHA_MODE_PREMULTIPLIED : DXGI_ALPHA_MODE_IGNORE;

  Presenter presenter;
  presenter.hwnd = hwnd;
  HRESULT hr = composed
                   ? factory->CreateSwapChainForComposition(device_, &desc, nullptr,
                                                            &presenter.swap)
                   : factory->CreateSwapChainForHwnd(device_, hwnd, &desc, nullptr, nullptr,
                                                     &presenter.swap);
  if (FAILED(hr)) {
    std::cerr << "[Canvas] swapchain creation failed: 0x" << std::hex << hr << std::dec
              << std::endl;
    DestroyWindow(hwnd);
    return false;
  }
  if (!composed) factory->MakeWindowAssociation(hwnd, DXGI_MWA_NO_ALT_ENTER);

  Microsoft::WRL::ComPtr<ID3D11Texture2D> back_buffer;
  if (FAILED(presenter.swap->GetBuffer(0, IID_PPV_ARGS(&back_buffer))) ||
      FAILED(device_->CreateRenderTargetView(back_buffer.Get(), nullptr, &presenter.target))) {
    DestroyWindow(hwnd);
    return false;
  }

  if (composed) {
    if (FAILED(dcomp_->CreateTargetForHwnd(hwnd, TRUE, &presenter.comp_target)) ||
        FAILED(dcomp_->CreateVisual(&presenter.visual)) ||
        FAILED(presenter.visual->SetContent(presenter.swap.Get())) ||
        FAILED(presenter.comp_target->SetRoot(presenter.visual.Get())) ||
        FAILED(dcomp_->Commit())) {
      std::cerr << "[Canvas] DirectComposition setup failed" << std::endl;
      DestroyWindow(hwnd);
      return false;
    }
    // Nothing is drawn before the first canvas frame; present one transparent
    // buffer so the window never flashes undefined content.
    const float clear[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    context_->ClearRenderTargetView(presenter.target.Get(), clear);
    presenter.swap->Present(0, 0);
  }

  presenter.crop[0] = u0;
  presenter.crop[1] = v0;
  presenter.crop[2] = u1 - u0;
  presenter.crop[3] = v1 - v0;
  presenters_.push_back(std::move(presenter));

  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd, HWND_TOPMOST, left, top, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  return true;
}

void CanvasPresenterSet::NotifyMenu(int index, int command) {
  if (menu_handler_) menu_handler_(index, command);
}

void CanvasPresenterSet::DestroyPresenter(Presenter& presenter) {
  // Composition objects must go before the swapchain they hold; the window keeps
  // working without them, so releasing in this order never invalidates the HWND.
  presenter.visual.Reset();
  presenter.comp_target.Reset();
  presenter.target.Reset();
  presenter.swap.Reset();
  if (presenter.hwnd) {
    DestroyWindow(presenter.hwnd);
    presenter.hwnd = nullptr;
  }
}

void CanvasPresenterSet::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& presenter : presenters_) DestroyPresenter(presenter);
  presenters_.clear();
  canvas_view_.Reset();
  canvas_texture_ = nullptr;
}

void CanvasPresenterSet::QueueFrame(ID3D11Texture2D* canvas) {
  if (!canvas) return;
  std::lock_guard<std::mutex> lock(pending_mutex_);
  pending_frame_ = canvas;
  has_pending_frame_ = true;
}

void CanvasPresenterSet::PresentQueued() {
  Microsoft::WRL::ComPtr<ID3D11Texture2D> frame;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    if (!has_pending_frame_) return;
    has_pending_frame_ = false;
    frame = pending_frame_;
  }
  Present(frame.Get());
}

void CanvasPresenterSet::PresentAllQueued() {
  // Held for the whole pass: a destroyed set must not leave a dangling entry
  // between the copy and the call.
  std::lock_guard<std::mutex> lock(g_live_sets_mutex);
  for (auto* set : g_live_sets) set->PresentQueued();
}

void CanvasPresenterSet::Present(ID3D11Texture2D* canvas) {
  if (!canvas) return;
  std::lock_guard<std::mutex> lock(mutex_);
  if (presenters_.empty()) return;

  if (canvas_texture_ != canvas || !canvas_view_) {
    canvas_view_.Reset();
    if (FAILED(device_->CreateShaderResourceView(canvas, nullptr, &canvas_view_))) return;
    canvas_texture_ = canvas;
  }

  context_->OMSetBlendState(nullptr, nullptr, 0xFFFFFFFF);
  context_->RSSetState(rasterizer_.Get());
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->IASetInputLayout(nullptr);
  context_->VSSetShader(vertex_shader_.Get(), nullptr, 0);
  context_->PSSetShader(pixel_shader_.Get(), nullptr, 0);
  context_->PSSetSamplers(0, 1, sampler_.GetAddressOf());
  ID3D11ShaderResourceView* views[] = {canvas_view_.Get()};
  context_->PSSetShaderResources(0, 1, views);

  for (auto& presenter : presenters_) {
    if (!presenter.swap || !presenter.target) continue;
    RECT client{};
    GetClientRect(presenter.hwnd, &client);
    D3D11_VIEWPORT viewport{};
    viewport.Width = static_cast<float>(client.right - client.left);
    viewport.Height = static_cast<float>(client.bottom - client.top);
    viewport.MaxDepth = 1.0f;
    context_->RSSetViewports(1, &viewport);
    context_->UpdateSubresource(crop_buffer_.Get(), 0, nullptr, presenter.crop, 0, 0);
    context_->PSSetConstantBuffers(0, 1, crop_buffer_.GetAddressOf());
    ID3D11RenderTargetView* targets[] = {presenter.target.Get()};
    context_->OMSetRenderTargets(1, targets, nullptr);
    context_->Draw(3, 0);
    presenter.swap->Present(0, 0);
  }
  DwmFlush();
}

// ---------------- Mirror windows (CanvasMirrorSet) ----------------
//
// A live mirror + remote control for far-away cast screens: a normal desktop
// window samples the material's region of the same canvas texture, and mouse
// and keyboard events are mapped back into the same CEF instance, so what the
// operator sees and clicks is exactly what is being cast. Unlike presenters
// these windows have a real (closable, resizable) title bar and can take
// keyboard focus; presenters stay NOACTIVATE and click-through.

namespace {

// Every live mirror set, so the CEF pump tick can flush queued frames. Same
// pattern as the presenter sets; destruction guards against pump traversal.
std::mutex g_live_mirrors_mutex;
std::vector<CanvasMirrorSet*> g_live_mirrors;

constexpr wchar_t kMirrorClass[] = L"EnodeCanvasMirror";

struct MirrorBinding {
  CanvasMirrorSet* owner;
  size_t index;
};

void EnsureMirrorWindowClass() {
  static std::once_flag once;
  std::call_once(once, [] {
    WNDCLASSEXW wc = {sizeof(WNDCLASSEXW)};
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = CanvasMirrorSet::MirrorProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kMirrorClass;
    RegisterClassExW(&wc);
  });
}

// CEF reports only the cursor *type* (and a handle that dies with the
// callback), so standard system cursors are picked by type. Custom CSS
// cursors (CT_CUSTOM) fall back to the arrow.
HCURSOR CursorForCefType(int type) {
  switch (type) {
    case CT_CROSS:
    case CT_CELL:
      return LoadCursorW(nullptr, IDC_CROSS);
    case CT_HAND:
      return LoadCursorW(nullptr, IDC_HAND);
    case CT_IBEAM:
    case CT_VERTICALTEXT:
      return LoadCursorW(nullptr, IDC_IBEAM);
    case CT_WAIT:
      return LoadCursorW(nullptr, IDC_WAIT);
    case CT_HELP:
      return LoadCursorW(nullptr, IDC_HELP);
    case CT_EASTRESIZE:
    case CT_WESTRESIZE:
    case CT_EASTWESTRESIZE:
    case CT_COLUMNRESIZE:
      return LoadCursorW(nullptr, IDC_SIZEWE);
    case CT_NORTHRESIZE:
    case CT_SOUTHRESIZE:
    case CT_NORTHSOUTHRESIZE:
    case CT_ROWRESIZE:
      return LoadCursorW(nullptr, IDC_SIZENS);
    case CT_NORTHEASTRESIZE:
    case CT_SOUTHWESTRESIZE:
    case CT_NORTHEASTSOUTHWESTRESIZE:
      return LoadCursorW(nullptr, IDC_SIZENESW);
    case CT_NORTHWESTRESIZE:
    case CT_SOUTHEASTRESIZE:
    case CT_NORTHWESTSOUTHEASTRESIZE:
      return LoadCursorW(nullptr, IDC_SIZENWSE);
    case CT_MOVE:
    case CT_MIDDLEPANNING:
    case CT_EASTPANNING:
    case CT_NORTHPANNING:
    case CT_NORTHEASTPANNING:
    case CT_NORTHWESTPANNING:
    case CT_SOUTHPANNING:
    case CT_SOUTHEASTPANNING:
    case CT_SOUTHWESTPANNING:
    case CT_WESTPANNING:
    case CT_GRAB:
    case CT_GRABBING:
      return LoadCursorW(nullptr, IDC_SIZEALL);
    case CT_PROGRESS:
      return LoadCursorW(nullptr, IDC_APPSTARTING);
    case CT_NODROP:
    case CT_NOTALLOWED:
    case CT_DND_NONE:
      return LoadCursorW(nullptr, IDC_NO);
    case CT_NONE:
      return nullptr;  // Page asked for a hidden pointer.
    default:
      return LoadCursorW(nullptr, IDC_ARROW);
  }
}

}  // namespace

CanvasMirrorSet::CanvasMirrorSet(ID3D11Device* device, CefRefPtr<CefBrowser> browser)
    : device_(device), browser_(std::move(browser)) {
  if (device_) device_->GetImmediateContext(&context_);
  std::lock_guard<std::mutex> lock(g_live_mirrors_mutex);
  g_live_mirrors.push_back(this);
}

CanvasMirrorSet::~CanvasMirrorSet() {
  Clear();
  std::lock_guard<std::mutex> lock(g_live_mirrors_mutex);
  g_live_mirrors.erase(std::remove(g_live_mirrors.begin(), g_live_mirrors.end(), this),
                       g_live_mirrors.end());
}

bool CanvasMirrorSet::Initialize() {
  if (!device_ || !context_) return false;
  Microsoft::WRL::ComPtr<ID3DBlob> vertex_blob;
  Microsoft::WRL::ComPtr<ID3DBlob> pixel_blob;
  Microsoft::WRL::ComPtr<ID3DBlob> error;
  HRESULT hr = D3DCompile(kShaderSource, sizeof(kShaderSource) - 1, nullptr, nullptr, nullptr,
                          "VSMain", "vs_4_0", 0, 0, &vertex_blob, &error);
  if (FAILED(hr)) return false;
  hr = D3DCompile(kShaderSource, sizeof(kShaderSource) - 1, nullptr, nullptr, nullptr,
                  "PSMain", "ps_4_0", 0, 0, &pixel_blob, &error);
  if (FAILED(hr)) return false;
  if (FAILED(device_->CreateVertexShader(vertex_blob->GetBufferPointer(),
                                         vertex_blob->GetBufferSize(), nullptr,
                                         &vertex_shader_)) ||
      FAILED(device_->CreatePixelShader(pixel_blob->GetBufferPointer(),
                                        pixel_blob->GetBufferSize(), nullptr,
                                        &pixel_shader_))) {
    return false;
  }

  D3D11_SAMPLER_DESC sampler_desc{};
  sampler_desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  sampler_desc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler_desc.ComparisonFunc = D3D11_COMPARISON_NEVER;
  sampler_desc.MaxLOD = D3D11_FLOAT32_MAX;
  if (FAILED(device_->CreateSamplerState(&sampler_desc, &sampler_))) return false;

  D3D11_BUFFER_DESC buffer_desc{};
  buffer_desc.ByteWidth = 16;
  buffer_desc.Usage = D3D11_USAGE_DEFAULT;
  buffer_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  if (FAILED(device_->CreateBuffer(&buffer_desc, nullptr, &crop_buffer_))) return false;

  D3D11_RASTERIZER_DESC rasterizer_desc{};
  rasterizer_desc.FillMode = D3D11_FILL_SOLID;
  rasterizer_desc.CullMode = D3D11_CULL_NONE;
  rasterizer_desc.DepthClipEnable = TRUE;
  if (FAILED(device_->CreateRasterizerState(&rasterizer_desc, &rasterizer_))) return false;
  return true;
}

bool CanvasMirrorSet::Open(const std::string& key, const std::wstring& title, int width,
                           int height, float u0, float v0, float u1, float v1,
                           int canvas_width, int canvas_height,
                           ID3D11Texture2D* initial_frame) {
  if (!device_ || width <= 0 || height <= 0 || canvas_width <= 0 || canvas_height <= 0) {
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    canvas_width_ = canvas_width;
    canvas_height_ = canvas_height;
    // Reopening the same material focuses the existing window, no rebuild.
    for (auto& mirror : mirrors_) {
      if (mirror.key == key && mirror.hwnd) {
        if (IsIconic(mirror.hwnd)) ShowWindow(mirror.hwnd, SW_RESTORE);
        SetForegroundWindow(mirror.hwnd);
        SetFocus(mirror.hwnd);
        return true;
      }
    }
  }
  EnsureMirrorWindowClass();
  HWND hwnd = CreateWindowExW(0, kMirrorClass, title.c_str(), WS_OVERLAPPEDWINDOW,
                              CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr,
                              GetModuleHandleW(nullptr), nullptr);
  if (!hwnd) {
    std::cerr << "[Canvas] mirror CreateWindowEx failed: " << GetLastError() << std::endl;
    return false;
  }
  // IME composition only reaches a window that owns an input context. The
  // mirror windows are created on the Flutter platform thread, so ask the
  // system for the thread's default context explicitly instead of relying on
  // CreateWindowEx to have attached one.
  ImmAssociateContextEx(hwnd, nullptr, IACE_DEFAULT);
  HIMC ime_context = ImmGetContext(hwnd);
  LogImeDebug("OPEN hwnd=%p ctx=%p\n", hwnd, ime_context);
  if (ime_context) ImmReleaseContext(hwnd, ime_context);
  RECT client{};
  GetClientRect(hwnd, &client);
  const int client_w = client.right - client.left;
  const int client_h = client.bottom - client.top;
  if (client_w <= 0 || client_h <= 0) {
    DestroyWindow(hwnd);
    return false;
  }

  DXGI_SWAP_CHAIN_DESC1 desc{};
  desc.Width = static_cast<UINT>(client_w);
  desc.Height = static_cast<UINT>(client_h);
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  desc.BufferCount = 2;
  desc.Scaling = DXGI_SCALING_STRETCH;
  desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  // Opaque window: the embedded page paints its own background, so unmapped
  // transparent pixels falling back to black read as a plain window.
  desc.AlphaMode = DXGI_ALPHA_MODE_IGNORE;

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  Microsoft::WRL::ComPtr<IDXGIFactory2> factory;
  Microsoft::WRL::ComPtr<IDXGISwapChain1> swap;
  HRESULT swap_hr = S_OK;
  if (FAILED(device_->QueryInterface(IID_PPV_ARGS(&dxgi_device))) ||
      FAILED(dxgi_device->GetAdapter(&adapter)) ||
      FAILED(adapter->GetParent(IID_PPV_ARGS(&factory))) ||
      FAILED(swap_hr = factory->CreateSwapChainForHwnd(device_, hwnd, &desc, nullptr, nullptr,
                                                       &swap))) {
    std::cerr << "[Canvas] mirror swapchain creation failed: 0x" << std::hex << swap_hr
              << std::dec << std::endl;
    DestroyWindow(hwnd);
    return false;
  }
  factory->MakeWindowAssociation(hwnd, DXGI_MWA_NO_ALT_ENTER);

  size_t index = mirrors_.size();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    // Reuse a dead slot (a window the user closed) so the vector stays small.
    Mirror* mirror = nullptr;
    for (size_t i = 0; i < mirrors_.size(); ++i) {
      if (!mirrors_[i].hwnd) {
        mirror = &mirrors_[i];
        index = i;
        break;
      }
    }
    if (!mirror) {
      mirrors_.emplace_back();
      mirror = &mirrors_.back();
      index = mirrors_.size() - 1;
    }
    mirror->key = key;
    mirror->hwnd = hwnd;
    mirror->swap = swap;
    mirror->crop[0] = u0;
    mirror->crop[1] = v0;
    mirror->crop[2] = u1 - u0;
    mirror->crop[3] = v1 - v0;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(new MirrorBinding{this, index}));
  }

  ShowWindow(hwnd, SW_SHOW);
  // The back-buffer view is created only now, after ShowWindow has delivered
  // the first WM_SIZE. A view held across that resize makes ResizeBuffers fail
  // (DXGI_ERROR_INVALID_CALL), which used to leave the mirror without a render
  // target and therefore permanently white.
  HandleResize(mirrors_[index]);
  // Draw one frame right away (whatever the presenters last drew) so a static
  // page does not wait for the next browser repaint.
  QueueFrame(initial_frame);
  PresentQueued();
  return true;
}

void CanvasMirrorSet::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& mirror : mirrors_) DestroyMirror(mirror);
  mirrors_.clear();
}

void CanvasMirrorSet::DestroyMirror(Mirror& mirror) {
  mirror.target.Reset();
  mirror.swap.Reset();
  if (mirror.hwnd) {
    // WM_NCDESTROY clears GWLP_USERDATA (the binding deletes itself). Null the
    // hwnd first so messages dispatched synchronously by DestroyWindow never
    // treat this slot as a live window again.
    HWND hwnd = mirror.hwnd;
    mirror.hwnd = nullptr;
    DestroyWindow(hwnd);
  }
}

void CanvasMirrorSet::RemoveAt(size_t index) {
  // The user closed the window; we are inside its WM_NCDESTROY. Drop only the
  // render resources and registration; the slot stays for reuse.
  if (index >= mirrors_.size()) return;
  mirrors_[index].target.Reset();
  mirrors_[index].swap.Reset();
  mirrors_[index].hwnd = nullptr;
}

void CanvasMirrorSet::SetCursorType(int cef_cursor_type) {
  cursor_type_.store(cef_cursor_type);
  // CEF calls this on its UI thread while the windows belong to the platform
  // thread: post a WM_SETCURSOR so each window applies it on its own thread.
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& mirror : mirrors_) {
    if (!mirror.hwnd) continue;
    PostMessageW(mirror.hwnd, WM_SETCURSOR, reinterpret_cast<WPARAM>(mirror.hwnd),
                 MAKELPARAM(HTCLIENT, WM_MOUSEMOVE));
  }
}

HCURSOR CanvasMirrorSet::CursorForMirror(size_t index) {
  if (index >= mirrors_.size() || !mirrors_[index].hwnd) {
    return LoadCursorW(nullptr, IDC_ARROW);
  }
  Mirror& mirror = mirrors_[index];
  // The page cursor only applies inside the material's region; the letterbox
  // bars are dead space (input there is dropped too), so keep the arrow.
  POINT pt{};
  RECT client{};
  if (GetCursorPos(&pt) && ScreenToClient(mirror.hwnd, &pt) &&
      GetClientRect(mirror.hwnd, &client)) {
    const float dst_w = static_cast<float>(client.right - client.left);
    const float dst_h = static_cast<float>(client.bottom - client.top);
    const float src_w = mirror.crop[2] * canvas_width_;
    const float src_h = mirror.crop[3] * canvas_height_;
    if (dst_w > 0.0f && dst_h > 0.0f && src_w > 0.0f && src_h > 0.0f) {
      const float scale = std::min(dst_w / src_w, dst_h / src_h);
      const float src_x = (pt.x - (dst_w - src_w * scale) * 0.5f) / scale;
      const float src_y = (pt.y - (dst_h - src_h * scale) * 0.5f) / scale;
      if (src_x < 0.0f || src_y < 0.0f || src_x >= src_w || src_y >= src_h) {
        return LoadCursorW(nullptr, IDC_ARROW);
      }
    }
  }
  return CursorForCefType(cursor_type_.load());
}

void CanvasMirrorSet::QueueFrame(ID3D11Texture2D* canvas) {
  if (!canvas) return;
  std::lock_guard<std::mutex> lock(pending_mutex_);
  pending_frame_ = canvas;
  has_pending_frame_ = true;
}

bool CanvasMirrorSet::HasFrame() {
  std::lock_guard<std::mutex> lock(mutex_);
  return canvas_texture_ != nullptr;
}

void CanvasMirrorSet::PresentQueued() {
  Microsoft::WRL::ComPtr<ID3D11Texture2D> frame;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    if (!has_pending_frame_) return;
    has_pending_frame_ = false;
    frame = pending_frame_;
  }
  Present(frame.Get());
}

void CanvasMirrorSet::PresentAllQueued() {
  std::lock_guard<std::mutex> lock(g_live_mirrors_mutex);
  for (auto* set : g_live_mirrors) set->PresentQueued();
}

void CanvasMirrorSet::Present(ID3D11Texture2D* canvas) {
  if (!canvas) return;
  std::lock_guard<std::mutex> lock(mutex_);
  if (mirrors_.empty()) return;

  if (canvas_texture_ != canvas || !canvas_view_) {
    canvas_view_.Reset();
    const HRESULT hr = device_->CreateShaderResourceView(canvas, nullptr, &canvas_view_);
    if (FAILED(hr)) {
      std::cerr << "[Canvas] mirror SRV creation failed: 0x" << std::hex << hr << std::dec
                << std::endl;
      return;
    }
    canvas_texture_ = canvas;
  }

  context_->OMSetBlendState(nullptr, nullptr, 0xFFFFFFFF);
  context_->RSSetState(rasterizer_.Get());
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->IASetInputLayout(nullptr);
  context_->VSSetShader(vertex_shader_.Get(), nullptr, 0);
  context_->PSSetShader(pixel_shader_.Get(), nullptr, 0);
  context_->PSSetSamplers(0, 1, sampler_.GetAddressOf());
  ID3D11ShaderResourceView* views[] = {canvas_view_.Get()};
  context_->PSSetShaderResources(0, 1, views);

  const float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};
  for (auto& mirror : mirrors_) {
    if (!mirror.swap || !mirror.target) continue;
    RECT client{};
    GetClientRect(mirror.hwnd, &client);
    const float dst_w = static_cast<float>(client.right - client.left);
    const float dst_h = static_cast<float>(client.bottom - client.top);
    const float src_w = mirror.crop[2] * canvas_width_;
    const float src_h = mirror.crop[3] * canvas_height_;
    if (dst_w <= 0.0f || dst_h <= 0.0f || src_w <= 0.0f || src_h <= 0.0f) continue;
    // OBS-style uniform fit: the window never reflows the page; it letterboxes
    // the material's fixed-size region into whatever the operator resized to.
    const float scale = std::min(dst_w / src_w, dst_h / src_h);
    D3D11_VIEWPORT viewport{};
    viewport.TopLeftX = (dst_w - src_w * scale) * 0.5f;
    viewport.TopLeftY = (dst_h - src_h * scale) * 0.5f;
    viewport.Width = src_w * scale;
    viewport.Height = src_h * scale;
    viewport.MaxDepth = 1.0f;
    context_->RSSetViewports(1, &viewport);
    context_->UpdateSubresource(crop_buffer_.Get(), 0, nullptr, mirror.crop, 0, 0);
    context_->PSSetConstantBuffers(0, 1, crop_buffer_.GetAddressOf());
    ID3D11RenderTargetView* targets[] = {mirror.target.Get()};
    context_->OMSetRenderTargets(1, targets, nullptr);
    context_->ClearRenderTargetView(mirror.target.Get(), black);
    context_->Draw(3, 0);
    const HRESULT hr = mirror.swap->Present(0, 0);
    if (FAILED(hr)) {
      static int logged = 0;
      if (logged++ < 3) {
        std::cerr << "[Canvas] mirror Present failed: 0x" << std::hex << hr << std::dec
                  << std::endl;
      }
    }
  }
  DwmFlush();
}

void CanvasMirrorSet::HandleResize(Mirror& mirror) {
  if (!mirror.swap) return;
  RECT client{};
  if (!GetClientRect(mirror.hwnd, &client)) return;
  const int w = client.right - client.left;
  const int h = client.bottom - client.top;
  if (w <= 0 || h <= 0) return;
  mirror.target.Reset();
  const HRESULT hr = mirror.swap->ResizeBuffers(0, static_cast<UINT>(w), static_cast<UINT>(h),
                                                DXGI_FORMAT_UNKNOWN, 0);
  if (FAILED(hr)) {
    std::cerr << "[Canvas] mirror ResizeBuffers failed: 0x" << std::hex << hr << std::dec
              << std::endl;
    return;
  }
  Microsoft::WRL::ComPtr<ID3D11Texture2D> back_buffer;
  if (FAILED(mirror.swap->GetBuffer(0, IID_PPV_ARGS(&back_buffer)))) return;
  device_->CreateRenderTargetView(back_buffer.Get(), nullptr, &mirror.target);
  // Redraw right after the resize instead of waiting for the next repaint.
  if (canvas_texture_) Present(canvas_texture_);
}

void CanvasMirrorSet::ForwardMouse(Mirror& mirror, UINT message, WPARAM wparam, LPARAM lparam) {
  if (!browser_) return;
  RECT client{};
  if (!GetClientRect(mirror.hwnd, &client)) return;
  const int client_w = client.right - client.left;
  const int client_h = client.bottom - client.top;
  if (client_w <= 0 || client_h <= 0 || canvas_width_ <= 0 || canvas_height_ <= 0) return;

  // WM_MOUSEWHEEL's lparam carries screen coordinates; every other mouse
  // message carries signed client coordinates in the low/high words.
  POINT pt{(int)(short)LOWORD(lparam), (int)(short)HIWORD(lparam)};
  if (message == WM_MOUSEWHEEL) ScreenToClient(mirror.hwnd, &pt);

  // Window client area -> the material's canvas rect, which is exactly the CEF
  // view space (canvas mode pins dpr to 1.0). Uses the same uniform fit as the
  // draw pass, so the pointer lands on the pixel the operator sees.
  const float src_w = mirror.crop[2] * canvas_width_;
  const float src_h = mirror.crop[3] * canvas_height_;
  if (src_w <= 0.0f || src_h <= 0.0f) return;
  const float scale = std::min(client_w / src_w, client_h / src_h);
  const float off_x = (client_w - src_w * scale) * 0.5f;
  const float off_y = (client_h - src_h * scale) * 0.5f;
  const float src_x = (pt.x - off_x) / scale;
  const float src_y = (pt.y - off_y) / scale;
  // The letterbox bars are outside the page; input there is dropped, the same
  // way OBS's interact window ignores it.
  if (src_x < 0.0f || src_y < 0.0f || src_x >= src_w || src_y >= src_h) return;
  if (message == WM_LBUTTONDOWN) mirror.ime_caret = pt;

  CefMouseEvent event;
  event.x = static_cast<int>(mirror.crop[0] * canvas_width_ + src_x);
  event.y = static_cast<int>(mirror.crop[1] * canvas_height_ + src_y);

  int modifiers = 0;
  if (wparam & MK_CONTROL) modifiers |= EVENTFLAG_CONTROL_DOWN;
  if (wparam & MK_SHIFT) modifiers |= EVENTFLAG_SHIFT_DOWN;
  if (GetKeyState(VK_MENU) & 0x8000) modifiers |= EVENTFLAG_ALT_DOWN;
  if (wparam & MK_LBUTTON) modifiers |= EVENTFLAG_LEFT_MOUSE_BUTTON;
  if (wparam & MK_RBUTTON) modifiers |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
  if (wparam & MK_MBUTTON) modifiers |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
  event.modifiers = modifiers;

  auto host = browser_->GetHost();
  switch (message) {
    case WM_MOUSEMOVE:
      host->SendMouseMoveEvent(event, false);
      break;
    case WM_MOUSEWHEEL:
      host->SendMouseWheelEvent(event, 0, static_cast<int>(GET_WHEEL_DELTA_WPARAM(wparam)));
      break;
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN: {
      const DWORD now = GetTickCount();
      if (now - mirror.last_click_tick <= GetDoubleClickTime() &&
          abs(event.x - mirror.last_click_x) <= 4 && abs(event.y - mirror.last_click_y) <= 4) {
        mirror.click_count = mirror.click_count >= 2 ? 1 : 2;
      } else {
        mirror.click_count = 1;
      }
      mirror.last_click_tick = now;
      mirror.last_click_x = event.x;
      mirror.last_click_y = event.y;
      SetFocus(mirror.hwnd);
      SetCapture(mirror.hwnd);
      host->SendMouseClickEvent(
          event,
          message == WM_LBUTTONDOWN ? MBT_LEFT : message == WM_RBUTTONDOWN ? MBT_RIGHT : MBT_MIDDLE,
          false, mirror.click_count);
      break;
    }
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
      if (GetCapture() == mirror.hwnd) ReleaseCapture();
      host->SendMouseClickEvent(
          event,
          message == WM_LBUTTONUP ? MBT_LEFT : message == WM_RBUTTONUP ? MBT_RIGHT : MBT_MIDDLE,
          true, mirror.click_count);
      break;
  }
}

LRESULT CALLBACK CanvasMirrorSet::MirrorProc(HWND hwnd, UINT message, WPARAM wparam,
                                             LPARAM lparam) {
  auto* binding = reinterpret_cast<MirrorBinding*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  // During creation the binding is not attached yet; default handling is fine
  // because no input that needs forwarding arrives that early.
  if (!binding || !binding->owner) return DefWindowProcW(hwnd, message, wparam, lparam);
  auto* self = binding->owner;

  if (message == WM_IME_STARTCOMPOSITION || message == WM_IME_COMPOSITION ||
      message == WM_IME_ENDCOMPOSITION || message == WM_IME_SETCONTEXT ||
      message == WM_IME_NOTIFY || message == WM_IME_CHAR) {
    LogImeDebug("MIRROR hwnd=%p msg=0x%04X wparam=0x%lX lparam=0x%lX\n", hwnd, message,
                static_cast<unsigned long>(wparam), static_cast<unsigned long>(lparam));
  }

  switch (message) {
    case WM_PAINT: {
      // No background brush plus manual Present: this only validates the
      // invalid region so WM_PAINT stops firing.
      PAINTSTRUCT paint;
      BeginPaint(hwnd, &paint);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_SETCURSOR:
      // Apply the page's CEF cursor (hand over links, I-beam over text...).
      // Returning TRUE keeps DefWindowProc from resetting it to the arrow.
      if (LOWORD(lparam) == HTCLIENT) {
        SetCursor(self->CursorForMirror(binding->index));
        return TRUE;
      }
      break;
    case WM_SIZE:
      // Skip during creation and while minimized (zero height).
      if (binding->index < self->mirrors_.size()) {
        self->HandleResize(self->mirrors_[binding->index]);
      }
      break;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYUP:
    case WM_CHAR:
    case WM_SYSCHAR:
    case WM_IME_SETCONTEXT:
    case WM_IME_COMPOSITION:
    case WM_IME_STARTCOMPOSITION:
    case WM_IME_ENDCOMPOSITION:
    case WM_SETFOCUS:
    case WM_KILLFOCUS: {
      const bool handled = SendKeyMessageToCef(self->browser_, hwnd, message, wparam, lparam);
      if (binding->index < self->mirrors_.size()) {
        // After SendKeyMessageToCef created the caret, park it where the user
        // clicked: Chinese IMEs read GetCaretPos for candidate placement.
        const auto& caret = self->mirrors_[binding->index].ime_caret;
        if (message == WM_IME_STARTCOMPOSITION) SetCaretPos(caret.x, caret.y);
      }
      if (message == WM_IME_ENDCOMPOSITION) DestroyCaret();
      if (handled) return 0;
      break;
    }
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
    case WM_MOUSEMOVE:
    case WM_MOUSEWHEEL:
      if (binding->index < self->mirrors_.size()) {
        self->ForwardMouse(self->mirrors_[binding->index], message, wparam, lparam);
      }
      if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN ||
          message == WM_MBUTTONDOWN) {
        return 0;
      }
      break;
    case WM_CLOSE:
      DestroyWindow(hwnd);
      return 0;
    case WM_NCDESTROY: {
      self->RemoveAt(binding->index);
      delete binding;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      return 0;
    }
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}
