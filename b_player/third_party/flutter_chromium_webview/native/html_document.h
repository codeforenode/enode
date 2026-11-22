#pragma once

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include "include/cef_cookie.h"
#include "include/cef_parser.h"
#include "include/cef_request_handler.h"
#include "include/cef_task.h"

namespace chromium_html {
inline constexpr size_t kMaxHtmlBytes = 4 * 1024 * 1024;

class Response : public CefResourceHandler {
 public:
  explicit Response(std::shared_ptr<const std::string> html) : html_(std::move(html)) {}
  bool Open(CefRefPtr<CefRequest>, bool& handle, CefRefPtr<CefCallback>) override {
    handle = true;
    return true;
  }
  void GetResponseHeaders(CefRefPtr<CefResponse> response, int64_t& length,
      CefString&) override {
    response->SetStatus(200);
    response->SetMimeType("text/html");
    response->SetCharset("utf-8");
    response->SetHeaderByName("Cache-Control", "no-store", true);
    response->SetHeaderByName("X-Content-Type-Options", "nosniff", true);
    length = static_cast<int64_t>(html_->size());
  }
  bool Read(void* out, int count, int& read, CefRefPtr<CefResourceReadCallback>) override {
    read = 0;
    if (count <= 0 || offset_ >= html_->size()) return false;
    read = static_cast<int>(std::min(static_cast<size_t>(count), html_->size() - offset_));
    std::memcpy(out, html_->data() + offset_, read);
    offset_ += read;
    return true;
  }
  bool Skip(int64_t count, int64_t& skipped, CefRefPtr<CefResourceSkipCallback>) override {
    if (count < 0) { skipped = -2; return false; }
    skipped = std::min(count, static_cast<int64_t>(html_->size() - offset_));
    offset_ += static_cast<size_t>(skipped);
    return true;
  }
  void Cancel() override {}
 private:
  const std::shared_ptr<const std::string> html_;
  size_t offset_ = 0;
  IMPLEMENT_REFCOUNTING(Response);
};

class Request : public CefResourceRequestHandler {
 public:
  explicit Request(std::shared_ptr<const std::string> html) : html_(std::move(html)) {}
  CefRefPtr<CefResourceHandler> GetResourceHandler(CefRefPtr<CefBrowser>,
      CefRefPtr<CefFrame>, CefRefPtr<CefRequest>) override { return new Response(html_); }
 private:
  const std::shared_ptr<const std::string> html_;
  IMPLEMENT_REFCOUNTING(Request);
};

inline std::string Trimmed(const std::string& value) {
  size_t begin = 0, end = value.size();
  while (begin < end && isspace(static_cast<unsigned char>(value[begin]))) ++begin;
  while (end > begin && isspace(static_cast<unsigned char>(value[end - 1]))) --end;
  return value.substr(begin, end - begin);
}

inline std::string Lowered(const std::string& value) {
  std::string out = value;
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char ch) { return static_cast<char>(tolower(ch)); });
  return out;
}

// Set-Cookie dates arrive in either HTTP wire format ("Sat, 18-Sep-2027
// 09:24:03 GMT" / "Thu, 01 Jan 2027 00:00:00 GMT"). Windows has no timegm, so
// the parsed fields are converted straight into Windows-epoch microseconds.
inline bool ParseHttpDate(const std::string& value, cef_basetime_t& out) {
  static const char* months[] = {"jan", "feb", "mar", "apr", "may", "jun",
                                 "jul", "aug", "sep", "oct", "nov", "dec"};
  int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
  std::string token;
  auto flush = [&]() {
    if (token.empty()) return;
    if (token.size() == 4 && isdigit(static_cast<unsigned char>(token[0])) &&
        isdigit(static_cast<unsigned char>(token[1])) &&
        isdigit(static_cast<unsigned char>(token[2])) &&
        isdigit(static_cast<unsigned char>(token[3]))) {
      if (!year) year = atoi(token.c_str());
    } else if (token.size() == 3) {
      for (int i = 0; i < 12; ++i) {
        if (!month && Lowered(token) == months[i]) month = i + 1;
      }
    } else if (token.find(':') != std::string::npos) {
      const size_t first = token.find(':');
      const size_t last = token.find(':', first + 1);
      hour = atoi(token.substr(0, first).c_str());
      minute = atoi(token.substr(first + 1, last - first - 1).c_str());
      second = last == std::string::npos ? 0 : atoi(token.substr(last + 1).c_str());
    } else if (token.size() <= 2 && isdigit(static_cast<unsigned char>(token[0]))) {
      if (!day) day = atoi(token.c_str());
    }
    token.clear();
  };
  for (const char ch : value) {
    if (ch == ' ' || ch == ',' || ch == '-' || ch == '/') flush();
    else token += ch;
  }
  flush();
  if (year < 1601 || !month || !day) return false;
  year -= month <= 2;
  const int64_t era = (year >= 0 ? year : year - 399) / 400;
  const int64_t yoe = year - era * 400;
  const int64_t doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
  const int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  const int64_t days = era * 146097 + doe - 719468;
  out.val = (days * 86400 + hour * 3600 + minute * 60 + second + 11644473600) * 1000000;
  return out.val > 0;
}

// Rebuilds a CefCookie from a Set-Cookie header, forcing the two attributes
// that third-party storage requires (SameSite=None, Secure). Cookies that
// already carry SameSite=None are left to the network stack; expiry is kept
// so the session survives hard kills, not just graceful shutdowns.
inline bool ParseCookieHeader(const std::string& header, bool secure, CefCookie& cookie) {
  const size_t attributes_pos = header.find(';');
  const std::string pair =
      header.substr(0, attributes_pos == std::string::npos ? header.size() : attributes_pos);
  const size_t equals = pair.find('=');
  if (equals == std::string::npos) return false;
  const std::string name = Trimmed(pair.substr(0, equals));
  if (name.empty()) return false;
  CefString(&cookie.name) = name;
  CefString(&cookie.value) = Trimmed(pair.substr(equals + 1));
  CefString(&cookie.path) = "/";
  cookie.priority = CEF_COOKIE_PRIORITY_MEDIUM;
  bool already_none = false;
  size_t pos = attributes_pos;
  while (pos != std::string::npos && pos + 1 < header.size()) {
    const size_t next = header.find(';', pos + 1);
    const std::string attribute = Trimmed(header.substr(
        pos + 1, (next == std::string::npos ? header.size() : next) - pos - 1));
    pos = next;
    if (attribute.empty()) continue;
    const size_t split = attribute.find('=');
    const std::string key = Lowered(Trimmed(
        split == std::string::npos ? attribute : attribute.substr(0, split)));
    const std::string value = split == std::string::npos ? std::string() : Trimmed(attribute.substr(split + 1));
    if (key == "samesite") {
      if (Lowered(value) == "none") already_none = true;
    } else if (key == "path" && !value.empty() && value.front() == '/') {
      CefString(&cookie.path) = value;
    } else if (key == "domain" && !value.empty()) {
      const std::string domain = value.front() == '.' ? value.substr(1) : value;
      if (domain.find('/') == std::string::npos) CefString(&cookie.domain) = domain;
    } else if (key == "secure") {
      cookie.secure = true;
    } else if (key == "httponly") {
      cookie.httponly = true;
    } else if (key == "expires" && !cookie.has_expires) {
      // A live expiry makes the relayed cookie persistent, so it reaches disk
      // on change instead of only at a graceful shutdown.
      cef_basetime_t parsed = {};
      if (ParseHttpDate(value, parsed)) {
        cookie.has_expires = true;
        cookie.expires = parsed;
      }
    } else if (key == "max-age" && !cookie.has_expires) {
      if (!value.empty() && value.find_first_not_of("-0123456789") == std::string::npos) {
        const long long seconds = strtoll(value.c_str(), nullptr, 10);
        cookie.has_expires = true;
        cookie.expires.val = cef_basetime_now().val + seconds * 1000000;
      }
    }
  }
  if (already_none) return false;
  cookie.same_site = CEF_COOKIE_SAME_SITE_NO_RESTRICTION;
  cookie.secure = secure;
  return true;
}

inline void RelaySetCookie(CefRefPtr<CefBrowser> browser, const std::string url, const CefCookie cookie) {
  const auto context = browser->GetHost()->GetRequestContext();
  if (!context) return;
  const auto manager = context->GetCookieManager(nullptr);
  if (!manager) return;
  manager->SetCookie(url, cookie, nullptr);
  // The store batches disk writes; without an explicit flush a hard kill
  // (power cut, task-manager end) would drop the relayed session.
  manager->FlushStore(nullptr);
}

// OnResourceResponse runs on the IO thread while the cookie manager is driven
// from the UI thread, so the relayed cookie travels there as a task.
class CookieStoreTask : public CefTask {
 public:
  CookieStoreTask(CefRefPtr<CefBrowser> browser, std::string url, CefCookie cookie)
      : browser_(std::move(browser)), url_(std::move(url)), cookie_(cookie) {}
  void Execute() override { RelaySetCookie(browser_, url_, cookie_); }
 private:
  const CefRefPtr<CefBrowser> browser_;
  const std::string url_;
  const CefCookie cookie_;
  IMPLEMENT_REFCOUNTING(CookieStoreTask);
};

// The canvas is a file:// document, so every cast page is a third-party
// frame. This Chromium build drops each Set-Cookie that lacks SameSite=None
// in that context, which silently discards the wemew QR-login session. Each
// sub-frame response carrying Set-Cookie is re-stored with explicit
// attributes through the frame's own request context.
class CookieRelay : public CefResourceRequestHandler {
 public:
  bool OnResourceResponse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                          CefRefPtr<CefRequest> request, CefRefPtr<CefResponse> response) override {
    if (!browser || !frame || frame->IsMain()) return false;
    const std::string url = request->GetURL().ToString();
    if (url.compare(0, 8, "https://") != 0) return false;
    CefResponse::HeaderMap headers;
    response->GetHeaderMap(headers);
    for (const auto& entry : headers) {
      if (Lowered(entry.first.ToString()) != "set-cookie") continue;
      CefCookie cookie = {};
      if (!ParseCookieHeader(entry.second.ToString(), true, cookie)) continue;
      fprintf(stderr, "[CefCookie] relay %s -> %s\n",
              CefString(&cookie.name).ToString().c_str(), url.c_str());
      CefPostTask(TID_UI, new CookieStoreTask(browser, url, cookie));
    }
    return false;
  }
 private:
  IMPLEMENT_REFCOUNTING(CookieRelay);
};

// UI writes and IO reads are synchronized. Each response owns an immutable
// snapshot, so replacement/disposal cannot invalidate an in-flight read.
class Documents : public CefRequestHandler {
 public:
  bool Set(const std::string& html, const std::string& url, std::string& canonical) {
    CefURLParts parts;
    if (html.size() > kMaxHtmlBytes || !CefParseURL(url, parts)) return false;
    const auto scheme = CefString(&parts.scheme).ToString();
    if ((scheme != "http" && scheme != "https") ||
        CefString(&parts.host).empty() || !CefString(&parts.username).empty() ||
        !CefString(&parts.password).empty() || url.find('#') != std::string::npos)
      return false;
    canonical = CefString(&parts.spec).ToString();
    auto data = std::make_shared<const std::string>(html);
    std::lock_guard<std::mutex> lock(mutex_);
    url_ = canonical;
    html_ = std::move(data);
    return true;
  }
  void Clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    html_.reset();
    url_.clear();
  }
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
      CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
      bool navigation, bool download, const CefString&, bool& disable_default) override {
    if (frame && frame->IsMain()) {
      if (!navigation || download || request->GetResourceType() != RT_MAIN_FRAME ||
          request->GetMethod() != "GET")
        return nullptr;
      std::lock_guard<std::mutex> lock(mutex_);
      if (!html_ || request->GetURL().ToString() != url_) return nullptr;
      disable_default = true;
      return new Request(html_);
    }
    // Third-party frame traffic: keep default loading but observe responses so
    // Set-Cookie can be re-stored with SameSite=None (see CookieRelay).
    static CefRefPtr<CookieRelay> relay = new CookieRelay();
    return relay;
  }
 private:
  std::mutex mutex_;
  std::string url_;
  std::shared_ptr<const std::string> html_;
  IMPLEMENT_REFCOUNTING(Documents);
};
}  // namespace chromium_html
