#ifndef FLUTTER_CHROMIUM_WEBVIEW_CANVAS_PRESENTER_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CANVAS_PRESENTER_H_

#include <windows.h>
#include <d3d11.h>
#include <dcomp.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <functional>
#include <memory>
#include <mutex>
#include <vector>

// One canvas texture, N native output windows. Each presenter owns a flip-model
// swapchain on a borderless topmost window and draws the canvas through a
// full-screen triangle with a UV crop, so every screen shows the same frame.
// The swapchain is composited by DirectComposition with premultiplied alpha, so
// transparent page pixels show the desktop underneath instead of black.
class CanvasPresenterSet {
 public:
  // Right-click menu command ids, mirrored by CastCanvas in Dart.
  static constexpr int kMenuCloseScreen = 1;
  static constexpr int kMenuCloseAll = 2;

  using MenuHandler = std::function<void(int index, int command)>;

  explicit CanvasPresenterSet(ID3D11Device* device);
  ~CanvasPresenterSet();

  bool Initialize();
  bool Add(int left, int top, int width, int height,
           float u0, float v0, float u1, float v1);
  void Clear();
  size_t count() const { return presenters_.size(); }

  void Present(ID3D11Texture2D* canvas);

  // CEF paint callbacks must stay cheap: they only hand over the newest frame.
  // The actual composite runs on the CEF pump tick, outside every CEF callback,
  // so D3D/DWM work can never re-enter the browser's own message processing.
  void QueueFrame(ID3D11Texture2D* canvas);
  void PresentQueued();

  // Called once per CEF pump tick; presents every set that has a queued frame.
  static void PresentAllQueued();

  // Window proc -> Dart. Runs on the thread that owns the presenter windows.
  void SetMenuHandler(MenuHandler handler) { menu_handler_ = std::move(handler); }
  void NotifyMenu(int index, int command);

 private:
  struct Presenter {
    HWND hwnd = nullptr;
    Microsoft::WRL::ComPtr<IDXGISwapChain1> swap;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> target;
    // The target keeps the visual tree bound to this window; releasing it would
    // detach the composition even though the visual is still alive.
    Microsoft::WRL::ComPtr<IDCompositionTarget> comp_target;
    Microsoft::WRL::ComPtr<IDCompositionVisual> visual;
    float crop[4] = {0.0f, 0.0f, 1.0f, 1.0f};
  };

  void DestroyPresenter(Presenter& presenter);

  ID3D11Device* device_;
  ID3D11DeviceContext* context_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_shader_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> crop_buffer_;
  Microsoft::WRL::ComPtr<ID3D11RasterizerState> rasterizer_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> canvas_view_;
  Microsoft::WRL::ComPtr<IDCompositionDevice> dcomp_;
  ID3D11Texture2D* canvas_texture_ = nullptr;
  std::vector<Presenter> presenters_;
  MenuHandler menu_handler_;
  std::mutex mutex_;

  Microsoft::WRL::ComPtr<ID3D11Texture2D> pending_frame_;
  bool has_pending_frame_ = false;
  std::mutex pending_mutex_;
};

#endif  // FLUTTER_CHROMIUM_WEBVIEW_CANVAS_PRESENTER_H_
