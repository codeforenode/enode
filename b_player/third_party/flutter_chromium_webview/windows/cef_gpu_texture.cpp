#include "include/cef_gpu_texture.h"

#include <dxgi1_2.h>
#include <iostream>
#include <new>

namespace {

FlutterDesktopGpuSurfaceDescriptor MakeDescriptor(HANDLE handle, int width, int height) {
  FlutterDesktopGpuSurfaceDescriptor d{};
  d.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  d.handle = handle;
  d.width = static_cast<size_t>(width);
  d.height = static_cast<size_t>(height);
  d.visible_width = static_cast<size_t>(width);
  d.visible_height = static_cast<size_t>(height);
  d.format = kFlutterDesktopPixelFormatBGRA8888;
  return d;
}

}  // namespace

ChromiumGpuDevice* ChromiumGpuDevice::Get() {
  static ChromiumGpuDevice device;
  return &device;
}

ChromiumGpuDevice::ChromiumGpuDevice() {
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
  D3D_FEATURE_LEVEL got = D3D_FEATURE_LEVEL_11_0;
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels,
                                 ARRAYSIZE(levels), D3D11_SDK_VERSION, &device_, &got, &context_);
  if (FAILED(hr)) {
    std::cerr << "[CEF] D3D11CreateDevice failed: 0x" << std::hex << hr << std::dec << std::endl;
  }
}

ChromiumGpuDevice::~ChromiumGpuDevice() = default;

FlutterChromiumGpuTexture::FlutterChromiumGpuTexture() {
  variant_ = std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
      kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
      [this](size_t width, size_t height) { return this->ObtainDescriptor(width, height); }));
}

FlutterChromiumGpuTexture::~FlutterChromiumGpuTexture() {
  texture_.Reset();
  shared_handle_ = nullptr;
}

flutter::TextureVariant* FlutterChromiumGpuTexture::GetTextureVariant() {
  return variant_.get();
}

bool FlutterChromiumGpuTexture::EnsureTexture(int width, int height) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (texture_ && width_ == width && height_ == height) return true;

  auto* device = ChromiumGpuDevice::Get()->device();
  if (!device) return false;
  Microsoft::WRL::ComPtr<ID3D11Device1> device1;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&device1)))) return false;

  D3D11_TEXTURE2D_DESC desc{};
  desc.Width = static_cast<UINT>(width);
  desc.Height = static_cast<UINT>(height);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  // Flutter's Windows embedder binds the surface through ANGLE using the legacy
  // GetSharedHandle below, and ANGLE only accepts textures created with
  // D3D11_RESOURCE_MISC_SHARED. MISC_SHARED and MISC_SHARED_KEYEDMUTEX cannot be
  // combined (E_INVALIDARG), and the engine never takes the keyed mutex anyway.
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  Microsoft::WRL::ComPtr<ID3D11Texture2D> texture;
  HRESULT hr = device->CreateTexture2D(&desc, nullptr, &texture);
  if (FAILED(hr)) {
    std::cerr << "[CEF] CreateTexture2D failed: 0x" << std::hex << hr << std::dec << std::endl;
    return false;
  }
  Microsoft::WRL::ComPtr<IDXGIResource> resource;
  if (FAILED(texture.As(&resource))) return false;
  HANDLE handle = nullptr;
  hr = resource->GetSharedHandle(&handle);
  if (FAILED(hr) || !handle) {
    std::cerr << "[CEF] GetSharedHandle failed: 0x" << std::hex << hr << std::dec << std::endl;
    return false;
  }

  // Legacy shared handles are owned by the resource; never close them by hand.
  texture_ = std::move(texture);
  shared_handle_ = handle;
  width_ = width;
  height_ = height;
  return true;
}

bool FlutterChromiumGpuTexture::OnSharedFrame(void* shared_handle, int width, int height) {
  if (!shared_handle || width <= 0 || height <= 0 || width > 16384 || height > 16384) return false;
  auto* device = ChromiumGpuDevice::Get()->device();
  auto* context = ChromiumGpuDevice::Get()->context();
  if (!device || !context) return false;

  Microsoft::WRL::ComPtr<ID3D11Device1> device1;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(&device1)))) return false;

  // CEF's texture has no keyed mutex and the handle dies with the callback.
  Microsoft::WRL::ComPtr<ID3D11Texture2D> source;
  HRESULT open = device1->OpenSharedResource1(shared_handle, IID_PPV_ARGS(&source));
  if (FAILED(open)) {
    static int logged = 0;
    if (logged++ < 3) std::cerr << "[CEF] OpenSharedResource1 failed: 0x" << std::hex << open << std::dec << std::endl;
    return false;
  }

  D3D11_TEXTURE2D_DESC source_desc{};
  source->GetDesc(&source_desc);
  if (source_desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM &&
      source_desc.Format != DXGI_FORMAT_R8G8B8A8_UNORM) {
    std::cerr << "[CEF] unexpected shared texture format " << source_desc.Format << std::endl;
  }

  if (!EnsureTexture(width, height)) return false;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> target;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    target = texture_;
  }
  if (!target) return false;

  // CopyResource requires matching formats; CEF delivers BGRA8 on Windows.
  context->CopyResource(target.Get(), source.Get());
  context->Flush();
  return true;
}

const FlutterDesktopGpuSurfaceDescriptor* FlutterChromiumGpuTexture::ObtainDescriptor(
    size_t width, size_t height) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!shared_handle_ || width_ <= 0 || height_ <= 0) return nullptr;
  // The engine copies the fields and calls release_callback; the handle itself
  // stays valid for our whole lifetime.
  auto* lease = new (std::nothrow) FlutterDesktopGpuSurfaceDescriptor(
      MakeDescriptor(shared_handle_, width_, height_));
  if (!lease) return nullptr;
  lease->release_callback = [](void* context) {
    delete static_cast<FlutterDesktopGpuSurfaceDescriptor*>(context);
  };
  lease->release_context = lease;
  return lease;
}
