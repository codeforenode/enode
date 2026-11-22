#ifndef FLUTTER_CHROMIUM_WEBVIEW_CEF_BROWSER_HANDLER_H_
#define FLUTTER_CHROMIUM_WEBVIEW_CEF_BROWSER_HANDLER_H_

#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include <atomic>
#include <functional>
#include <vector>
#include <flutter/texture_registrar.h>
#include <flutter/standard_method_codec.h>
#include "cef_texture.h"
#include "canvas_presenter.h"
#include "pending_callbacks.h"
#include "../../native/javascript_bridge.h"
#include "../../native/html_document.h"
#include "../../native/browser_settings.h"

class CefBrowserHandler : public CefClient,
                          public CefRenderHandler,
                          public CefLifeSpanHandler,
                          public CefDisplayHandler,
                          public CefLoadHandler,
                          public CefJSDialogHandler,
                          public CefContextMenuHandler,
                          public CefFocusHandler {
 public:
  using EventCallback = std::function<void(const char* event_name, flutter::EncodableMap args)>;
  
  CefBrowserHandler(flutter::TextureRegistrar* registrar, 
                    ChromiumFrameTexture* texture, 
                    ChromiumFrameTexture* popup_texture, 
                    int64_t texture_id,
                    int64_t popup_texture_id,
                    EventCallback on_event);
  ~CefBrowserHandler() override;
  chromium_bridge::Policy javascript_policy;
  CefRefPtr<chromium_settings::UserAgent> user_agent = new chromium_settings::UserAgent();
  CefRefPtr<chromium_html::Documents> html_documents = new chromium_html::Documents();
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return html_documents; }
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
      CefProcessId source, CefRefPtr<CefProcessMessage> message) override;

  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
  CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }

  // Asynchronously created browsers report readiness here. Persistent request
  // contexts finish loading on the message loop, so creation cannot be sync.
  void SetCreatedCallback(std::function<void()> callback) { created_callback_ = std::move(callback); }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id,
                    const CefString& target_url, const CefString& target_frame_name, WindowOpenDisposition target_disposition,
                    bool user_gesture, const CefPopupFeatures& popupFeatures, CefWindowInfo& windowInfo,
                    CefRefPtr<CefClient>& client, CefBrowserSettings& settings,
                    CefRefPtr<CefDictionaryValue>& extra_info, bool* no_javascript_access) override;

  void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect& rect) override;
  bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& info) override;
  bool GetScreenPoint(CefRefPtr<CefBrowser> browser, int view_x, int view_y,
                      int& screen_x, int& screen_y) override;
  void OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type,
               const RectList& dirtyRects, const void* buffer, int width, int height) override;
  void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser, PaintElementType type,
                          const RectList& dirtyRects,
                          const CefAcceleratedPaintInfo& info) override;
  void OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) override;
  void OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect& rect) override;
  bool StartDragging(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDragData> drag_data,
                     DragOperationsMask allowed_ops, int x, int y) override;
  void UpdateDragCursor(CefRefPtr<CefBrowser> browser, DragOperation operation) override;

  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  bool OnCursorChange(CefRefPtr<CefBrowser> browser, CefCursorHandle cursor,
                      cef_cursor_type_t type, const CefCursorInfo& custom_cursor_info) override;
  
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override;
  void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode errorCode,
                   const CefString& errorText, const CefString& failedUrl) override;
  
  bool OnJSDialog(CefRefPtr<CefBrowser> browser, const CefString& origin_url,
                  JSDialogType dialog_type, const CefString& message_text,
                  const CefString& default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback, bool& suppress_message) override;
  void OnResetDialogState(CefRefPtr<CefBrowser> browser) override;
  void OnContextMenuDismissed(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame) override;

  bool RunContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model,
                      CefRefPtr<CefRunContextMenuCallback> callback) override;

  void OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next) override;

  void CloseJSDialog(int dialog_id, bool success, const std::string& user_input);
  void CloseContextMenu(int menu_id, int command_id);
  void SetSize(int width, int height);
  void SetDevicePixelRatio(float dpr);
  void SetPresenters(std::shared_ptr<CanvasPresenterSet> presenters) {
    std::lock_guard<std::mutex> lock(presenters_mutex_);
    presenters_ = std::move(presenters);
  }
  // Paint callbacks run on CEF's UI thread while Close() runs on the platform
  // thread; both touch presenters_, so every access goes through the mutex and
  // a local copy keeps the set alive across Present().
  std::shared_ptr<CanvasPresenterSet> TakePresenters() {
    std::lock_guard<std::mutex> lock(presenters_mutex_);
    return presenters_;
  }
  void DropPresenters() {
    std::shared_ptr<CanvasPresenterSet> dropped;
    {
      std::lock_guard<std::mutex> lock(presenters_mutex_);
      dropped = std::move(presenters_);
    }
    if (dropped) dropped->Clear();
  }
  // The interaction-window mirror draws this same texture every frame, exactly
  // like the presenters do (OBS renders one browser source into several
  // displays); paint callbacks feed it so it never shows a stale frame.
  void SetMirror(std::shared_ptr<CanvasMirrorSet> mirror) {
    std::lock_guard<std::mutex> lock(mirror_mutex_);
    mirror_ = std::move(mirror);
  }
  std::shared_ptr<CanvasMirrorSet> TakeMirror() {
    std::lock_guard<std::mutex> lock(mirror_mutex_);
    return mirror_;
  }
  // Newest canvas texture (our copy of the CEF shared texture). Null before the
  // first accelerated frame.
  ID3D11Texture2D* CanvasTexture() const {
    return texture_ ? texture_->GetD3DTexture() : nullptr;
  }
  // Settings-editor preview: in canvas mode frames normally go only to the
  // native presenters. While the editor shows a Texture of this browser, the
  // texture must also get frame-available notifications, or it would stay at
  // its first frame (black).
  void SetFlutterPreview(bool on) { flutter_preview_ = on; }
  bool FlutterPreview() const { return flutter_preview_; }
  void Close(std::function<void()> on_closed = {});
  
  CefRefPtr<CefBrowser> GetBrowser() const { return closing_ ? nullptr : browser_; }

 private:
  void UnregisterTextures();
  flutter::TextureRegistrar* registrar_;
  ChromiumFrameTexture* texture_;
  ChromiumFrameTexture* popup_texture_;
  std::shared_ptr<CanvasPresenterSet> presenters_;
  std::mutex presenters_mutex_;
  std::shared_ptr<CanvasMirrorSet> mirror_;
  std::mutex mirror_mutex_;
  int64_t texture_id_;
  int64_t popup_texture_id_;
  std::atomic<bool> flutter_preview_{false};
  
  bool registered_ = true;
  bool closing_ = false;
  int width_ = 1;
  int height_ = 1;
  float dpr_ = 1;
  
  PendingCallbacks<CefRefPtr<CefJSDialogCallback>> pending_dialogs_;
  PendingCallbacks<CefRefPtr<CefRunContextMenuCallback>> pending_menus_;
  EventCallback on_event_;
  std::function<void()> created_callback_;
  CefRefPtr<CefBrowser> browser_;
  std::vector<std::function<void()>> close_callbacks_;
  
  IMPLEMENT_REFCOUNTING(CefBrowserHandler);
};

#endif
