#pragma once
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <utility>
#include "include/cef_browser.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/cef_request_context.h"

namespace chromium_settings {
inline bool ValidUserAgent(const std::string& value) {
  if (value.size() > 4096) return false;
  for (unsigned char ch : value) if (ch < 32 || ch == 127 || ch > 126) return false;
  return true;
}

// Every cast screen is a cross-site iframe, so Chromium treats its cookies as
// third-party and drops them by default (QR logins never see their session).
inline bool AllowAllCookies(CefRefPtr<CefRequestContext> context, std::string& error) {
  if (!context) { error = "no context"; return false; }
  auto value = CefValue::Create();
  value->SetInt(0);  // CookieControlsMode::kOff
  CefString detail;
  if (context->SetPreference("profile.cookie_controls_mode", value, detail)) return true;
  error = detail.ToString();
  auto flag = CefValue::Create();
  flag->SetBool(false);
  CefString fallback_detail;
  if (context->SetPreference("profile.block_third_party_cookies", flag, fallback_detail)) {
    error.clear();
    return true;
  }
  return false;
}

// SetPreference only reaches prefs the profile has registered, and on a fresh
// profile that happens after its asynchronous load. The stored value is read
// during that load, so seed it into the profile file before the context exists.
inline void SeedCookiePreferences(const std::string& profile_path) {
  if (profile_path.empty()) return;
  const std::filesystem::path file =
      std::filesystem::path(profile_path) / "Preferences";
  CefRefPtr<CefDictionaryValue> root;
  std::error_code ec;
  if (std::filesystem::exists(file, ec)) {
    std::ifstream in(file, std::ios::binary);
    std::stringstream buffer;
    buffer << in.rdbuf();
    auto parsed = CefParseJSON(buffer.str(), JSON_PARSER_RFC);
    if (parsed && parsed->GetType() == VTYPE_DICTIONARY) root = parsed->GetDictionary();
  }
  if (!root) root = CefDictionaryValue::Create();
  CefRefPtr<CefDictionaryValue> profile;
  auto existing_profile = root->GetValue("profile");
  if (existing_profile && existing_profile->GetType() == VTYPE_DICTIONARY) profile = existing_profile->GetDictionary();
  else profile = CefDictionaryValue::Create();
  bool changed = false;
  if (!(profile->HasKey("cookie_controls_mode") &&
        profile->GetType("cookie_controls_mode") == VTYPE_INT &&
        profile->GetInt("cookie_controls_mode") == 0)) {
    // CookieControlsMode::kOff: the cookie toggle in the site list is closed.
    profile->SetInt("cookie_controls_mode", 0);
    root->SetDictionary("profile", profile);
    changed = true;
  }
  CefRefPtr<CefDictionaryValue> protection;
  auto existing_protection = root->GetValue("tracking_protection");
  if (existing_protection && existing_protection->GetType() == VTYPE_DICTIONARY)
    protection = existing_protection->GetDictionary();
  else protection = CefDictionaryValue::Create();
  if (!(protection->HasKey("tracking_protection_3pcd_enabled") &&
        protection->GetType("tracking_protection_3pcd_enabled") == VTYPE_BOOL &&
        !protection->GetBool("tracking_protection_3pcd_enabled"))) {
    // This build has third-party cookie deprecation fully rolled out, which
    // starves cross-site cast frames of their session cookies.
    protection->SetBool("tracking_protection_3pcd_enabled", false);
    root->SetDictionary("tracking_protection", protection);
    changed = true;
  }
  if (!changed) return;
  auto value = CefValue::Create();
  value->SetDictionary(root);
  const auto json = CefWriteJSON(value, JSON_WRITER_DEFAULT);
  std::filesystem::create_directories(profile_path, ec);
  const auto tmp = file.string() + ".tmp";
  {
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out) return;
    out << json.ToString();
  }
  std::filesystem::remove(file, ec);
  std::filesystem::rename(tmp, file, ec);
}

// A custom autoplay policy lives in a fresh context, never the application's
// shared persistent context. Named profiles are on-disk (cookies, localStorage,
// IndexedDB, cache) and keep session cookies across restarts.
inline CefRefPtr<CefRequestContext> CustomContext(bool requires_gesture, const std::string& profile_name) {
  if (requires_gesture && profile_name.empty()) return nullptr;
  CefRequestContextSettings settings;
  settings.persist_session_cookies = 1;
  if (!profile_name.empty()) {
    // The global context reports its own profile dir (<root>/Default); profile
    // dirs must be children of the root, not nested inside another profile.
    std::filesystem::path base(CefRequestContext::GetGlobalContext()->GetCachePath().ToString());
    if (base.filename() == "Default") base = base.parent_path();
    if (!base.empty()) {
      // CEF only accepts a direct child of the root as a profile directory.
      CefString(&settings.cache_path) = (base / profile_name).string();
    }
  }
  const std::string cache_path = CefString(&settings.cache_path).ToString();
  if (!cache_path.empty()) SeedCookiePreferences(cache_path);
  auto created = CefRequestContext::CreateContext(settings, nullptr);
  fprintf(stderr, "[CefCtx] profile=%s cache=%s ctx=%p global=%d\n", profile_name.c_str(),
          CefString(&settings.cache_path).ToString().c_str(), created.get(),
          created ? created->IsGlobal() : -1);
  if (created) {
    std::string error;
    const bool ok = AllowAllCookies(created, error);
    fprintf(stderr, "[CefCtx] cookies allowed=%d err=%s\n", ok, error.c_str());
  }
  return created;
}
inline bool AllowAutoplay(CefRefPtr<CefBrowser> browser, std::string& error) {
  auto context = browser->GetHost()->GetRequestContext();
  auto value = CefValue::Create();
  value->SetBool(true);
  CefString detail;
  if (!context->SetPreference("media.autoplay_allowed", value, detail)) {
    error = detail.ToString(); return false;
  }
  value = CefValue::Create();
  value->SetBool(false);
  if (!context->SetPreference("media.block_autoplay", value, detail)) {
    error = detail.ToString(); return false;
  }
  return true;
}

class UserAgent : public CefDevToolsMessageObserver {
 public:
  using Done = std::function<void(bool, const std::string&)>;
  void Set(CefRefPtr<CefBrowser> browser, const std::string& value, Done done) {
    if (done_) { done(false, "A user-agent change is already pending"); return; }
    if (!ValidUserAgent(value)) { done(false, "User-agent must be printable ASCII within 4096 bytes"); return; }
    done_ = std::move(done);
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    auto parameters = CefDictionaryValue::Create();
    parameters->SetString("userAgent", value);
    // CEF delivers results asynchronously on the UI thread.
    message_id_ = browser->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setUserAgentOverride", parameters);
    if (!message_id_) Finish(false, "CEF could not submit the user-agent override");
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int id, bool success,
      const void* result, size_t size) override {
    if (id != message_id_ || !done_) return;
    Finish(success, success ? "" : (result && size
      ? std::string(static_cast<const char*>(result), size) : "CEF rejected the user-agent override"));
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    Finish(false, "DevTools agent detached before the user-agent change completed");
  }
  void Cancel() { Finish(false, "Browser closed before the user-agent change completed"); }
 private:
  void Finish(bool success, const std::string& error) {
    CefRefPtr<UserAgent> keep_alive = this;
    auto done = std::move(done_);
    done_ = {};
    message_id_ = 0;
    registration_ = nullptr;
    if (done) done(success, error);
  }
  Done done_;
  int message_id_ = 0;
  CefRefPtr<CefRegistration> registration_;
  IMPLEMENT_REFCOUNTING(UserAgent);
};
}  // namespace chromium_settings
