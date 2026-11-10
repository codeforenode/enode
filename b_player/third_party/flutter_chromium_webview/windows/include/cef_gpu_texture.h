#ifndef FLUTTER_CHROMIUM_WEBVIEW_CEF_GPU_TEXTURE_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CEF_GPU_TEXTURE_H_

#include <d3d11_1.h>
#include <wrl/client.h>

#include <memory>
#include <mutex>

#include "cef_texture.h"

// Process-wide D3D11 device. CEF's shared texture is opened here and copied
// into our own shared texture, which Flutter samples directly on the GPU.
class ChromiumGpuDevice {
 public:
  static ChromiumGpuDevice* Get();
  ID3D11Device* device() const { return device_.Get(); }
  ID3D11DeviceContext* context() const { return context_.Get(); }

 private:
  ChromiumGpuDevice();
  ~ChromiumGpuDevice();
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
};

class FlutterChromiumGpuTexture final : public ChromiumFrameTexture {
 public:
  FlutterChromiumGpuTexture();
  ~FlutterChromiumGpuTexture() override;

  flutter::TextureVariant* GetTextureVariant() override;
  bool OnSoftwareFrame(const void* buffer, int width, int height) override { return false; }

  // CEF's shared texture is pooled and recycled when the callback returns:
  // open and copy it immediately, never keep the handle.
  bool OnSharedFrame(void* shared_handle, int width, int height) override;
  ID3D11Texture2D* GetD3DTexture() override { return texture_.Get(); }

 private:
  bool EnsureTexture(int width, int height);
  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(size_t width, size_t height);

  std::mutex mutex_;
  std::unique_ptr<flutter::TextureVariant> variant_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> texture_;
  HANDLE shared_handle_ = nullptr;
  int width_ = 0;
  int height_ = 0;
};

#endif  // FLUTTER_CHROMIUM_WEBVIEW_CEF_GPU_TEXTURE_H_
