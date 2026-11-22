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
#include <string>
#include <vector>
#include <atomic>

#include "include/cef_browser.h"

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

  // The most recent canvas texture handed to Present(); lets a mirror show its
  // first frame immediately instead of waiting for the next browser repaint.
  ID3D11Texture2D* LastCanvasTexture() const { return canvas_texture_; }

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

// A normal, resizable desktop window that samples a crop of the same canvas
// texture the presenters show, and forwards mouse/keyboard input back into the
// shared CEF browser: the operator's live mirror and remote control of a
// far-away cast screen. Unlike presenters these windows have a real title bar,
// take focus, resize, and are closed by the user at any time. The cast screen
// itself stays click-through exactly as before.
class CanvasMirrorSet {
 public:
  CanvasMirrorSet(ID3D11Device* device, CefRefPtr<CefBrowser> browser);
  ~CanvasMirrorSet();

  bool Initialize();

  // Opens (or brings to front, when a mirror with this key is already open) a
  // mirror window of title x size, cropping [u0,v0,u1,v1] out of a
  // canvas_width x canvas_height canvas. initial_frame may be null; the window
  // then shows its first frame on the next queued canvas frame.
  bool Open(const std::string& key, const std::wstring& title, int width, int height,
            float u0, float v0, float u1, float v1,
            int canvas_width, int canvas_height, ID3D11Texture2D* initial_frame);

  // Destroys every mirror window; called when the canvas browser goes away.
  void Clear();

  void Present(ID3D11Texture2D* canvas);
  void QueueFrame(ID3D11Texture2D* canvas);
  void PresentQueued();
  static void PresentAllQueued();

  // True once a canvas frame has been drawn; the pump tick only has to supply
  // the first one (paint callbacks feed every later frame).
  bool HasFrame();

  // The page cursor reported by CEF (cef_cursor_type_t), applied to every open
  // mirror window. Presenters never show it: they are click-through.
  void SetCursorType(int cef_cursor_type);

  // Window proc for every mirror window; public only so the anonymous-namespace
  // window class registration can point at it.
  static LRESULT CALLBACK MirrorProc(HWND, UINT, WPARAM, LPARAM);

 private:
  struct Mirror {
    std::string key;
    HWND hwnd = nullptr;
    Microsoft::WRL::ComPtr<IDXGISwapChain1> swap;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> target;
    float crop[4] = {0.0f, 0.0f, 1.0f, 1.0f};  // u0, v0, du, dv
    // Double-click detection, same threshold as the Dart input path.
    DWORD last_click_tick = 0;
    int last_click_x = 0;
    int last_click_y = 0;
    int click_count = 0;
    // Last click in client pixels; the invisible IME caret sits here so the
    // candidate list opens next to the text box instead of the window corner.
    POINT ime_caret{0, 0};
  };

  void ForwardMouse(Mirror& mirror, UINT message, WPARAM wparam, LPARAM lparam);
  void HandleResize(Mirror& mirror);
  void DestroyMirror(Mirror& mirror);
  void RemoveAt(size_t index);
  HCURSOR CursorForMirror(size_t index);

  ID3D11Device* device_;
  ID3D11DeviceContext* context_;
  CefRefPtr<CefBrowser> browser_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_shader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_shader_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> crop_buffer_;
  Microsoft::WRL::ComPtr<ID3D11RasterizerState> rasterizer_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> canvas_view_;
  ID3D11Texture2D* canvas_texture_ = nullptr;
  int canvas_width_ = 0;
  int canvas_height_ = 0;
  std::vector<Mirror> mirrors_;
  std::mutex mutex_;

  // Written by CEF's UI thread, read by the mirror windows' thread.
  std::atomic<int> cursor_type_{0};  // CT_POINTER

  Microsoft::WRL::ComPtr<ID3D11Texture2D> pending_frame_;
  bool has_pending_frame_ = false;
  std::mutex pending_mutex_;
};

#endif  // FLUTTER_CHROMIUM_WEBVIEW_CANVAS_PRESENTER_H_
