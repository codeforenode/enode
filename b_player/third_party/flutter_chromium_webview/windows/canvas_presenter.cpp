#include "include/canvas_presenter.h"

#include <d3dcompiler.h>
#include <dwmapi.h>

#include <algorithm>
#include <iostream>
#include <new>
#include <thread>

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
