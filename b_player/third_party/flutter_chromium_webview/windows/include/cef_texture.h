#ifndef FLUTTER_CHROMIUM_WEBVIEW_CEF_TEXTURE_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CEF_TEXTURE_H_

#include <flutter/texture_registrar.h>
#include <mutex>
#include <memory>
#include <vector>

struct ID3D11Texture2D;

// Sink for rendered frames. CEF has two mutually exclusive delivery paths:
// software OnPaint (memory buffer) and OnAcceleratedPaint (a pooled shared
// texture handle that is recycled as soon as the callback returns).
class ChromiumFrameTexture {
 public:
  virtual ~ChromiumFrameTexture() = default;

  // Returns the texture variant to register with Flutter.
  virtual flutter::TextureVariant* GetTextureVariant() = 0;

  // Software path: BGRA pixels in memory.
  virtual bool OnSoftwareFrame(const void* buffer, int width, int height) = 0;

  // Accelerated path: copy the shared texture into our own; false means no new frame.
  virtual bool OnSharedFrame(void* shared_handle, int width, int height) = 0;

  // Owned D3D11 copy of the last accelerated frame, or null on the software path.
  virtual ID3D11Texture2D* GetD3DTexture() { return nullptr; }
};

class FlutterChromiumTexture final : public ChromiumFrameTexture {
 public:
  FlutterChromiumTexture();
  ~FlutterChromiumTexture() override;

  flutter::TextureVariant* GetTextureVariant() override;

  // Safely updates the internal buffer with BGRA data from CEF.
  // Converts BGRA to RGBA internally.
  bool OnSoftwareFrame(const void* buffer, int width, int height) override;
  bool OnSharedFrame(void* shared_handle, int width, int height) override { return false; }

 private:
  const FlutterDesktopPixelBuffer* CopyPixels(size_t width, size_t height);

  std::mutex mutex_;
  struct Frame {
    std::vector<uint8_t> pixels;
    size_t width;
    size_t height;
  };
  struct Lease {
    std::shared_ptr<const Frame> frame;
    FlutterDesktopPixelBuffer buffer;
  };
  std::shared_ptr<const Frame> frame_;
  
  std::unique_ptr<flutter::TextureVariant> variant_;
};

#endif  // FLUTTER_CHROMIUM_WEBVIEW_CEF_TEXTURE_H_
