#include "include/cef_keyboard.h"
#include <imm.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cstdarg>
#include <cstdio>

namespace {
struct HexText {
  std::string value;  // "len=2 text=4F60,597D"
};

HexText DumpComposition(HIMC context, DWORD type) {
  HexText out;
  const LONG bytes = ImmGetCompositionStringW(context, type, nullptr, 0);
  if (bytes <= 0) {
    out.value = "len=0";
    return out;
  }
  std::wstring text(static_cast<size_t>(bytes) / sizeof(wchar_t), L'\0');
  ImmGetCompositionStringW(context, type, text.data(), static_cast<DWORD>(bytes));
  char units[256] = {};
  size_t used = 0;
  for (size_t i = 0; i < text.size() && used + 8 < sizeof(units); ++i) {
    used += snprintf(units + used, sizeof(units) - used, i ? ",%04X" : "%04X",
                     static_cast<unsigned>(text[i]));
  }
  char header[32];
  snprintf(header, sizeof(header), "len=%ld text=", static_cast<long>(text.size()));
  out.value = std::string(header) + units;
  return out;
}
}

void LogImeDebug(const char* format, ...) {
  wchar_t dir[MAX_PATH] = {};
  if (GetTempPathW(MAX_PATH, dir) == 0) return;
  const std::wstring path = std::wstring(dir) + L"enode_ime.log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  char buffer[512];
  va_list args;
  va_start(args, format);
  int length = vsnprintf(buffer, sizeof(buffer) - 1, format, args);
  va_end(args);
  if (length < 0) length = 0;
  DWORD written = 0;
  WriteFile(file, buffer, static_cast<DWORD>(length), &written, nullptr);
  CloseHandle(file);
}

namespace {
int Modifiers(WPARAM key, LPARAM native) {
  int value = 0;
  if (GetKeyState(VK_SHIFT) & 0x8000) value |= EVENTFLAG_SHIFT_DOWN;
  if (GetKeyState(VK_CONTROL) & 0x8000) value |= EVENTFLAG_CONTROL_DOWN;
  if (GetKeyState(VK_MENU) & 0x8000) value |= EVENTFLAG_ALT_DOWN;
  if ((GetKeyState(VK_LWIN) & 0x8000) || (GetKeyState(VK_RWIN) & 0x8000)) value |= EVENTFLAG_COMMAND_DOWN;
  if (GetKeyState(VK_CAPITAL) & 1) value |= EVENTFLAG_CAPS_LOCK_ON;
  if (GetKeyState(VK_NUMLOCK) & 1) value |= EVENTFLAG_NUM_LOCK_ON;
  if ((key >= VK_NUMPAD0 && key <= VK_DIVIDE) || (key == VK_RETURN && (native & (1 << 24)))) value |= EVENTFLAG_IS_KEY_PAD;
  if (key == VK_LSHIFT || key == VK_LCONTROL || key == VK_LMENU) value |= EVENTFLAG_IS_LEFT;
  if (key == VK_RSHIFT || key == VK_RCONTROL || key == VK_RMENU) value |= EVENTFLAG_IS_RIGHT;
  return value;
}
std::wstring Composition(HIMC context, DWORD type) {
  const LONG bytes = ImmGetCompositionStringW(context, type, nullptr, 0);
  if (bytes <= 0) return {};
  std::wstring text(static_cast<size_t>(bytes) / sizeof(wchar_t), L'\0');
  ImmGetCompositionStringW(context, type, text.data(), static_cast<DWORD>(bytes));
  return text;
}

bool IsSelectionAttribute(char attribute) {
  return attribute == ATTR_TARGET_CONVERTED || attribute == ATTR_TARGET_NOTCONVERTED;
}

// Clause underlines for the candidate text, same as the CEF OSR sample: the
// converted (selected) clause is drawn thick, the rest thin.
std::vector<CefCompositionUnderline> CompositionUnderlines(HIMC context, size_t length,
                                                          uint32_t target_start,
                                                          uint32_t target_end) {
  std::vector<CefCompositionUnderline> underlines;
  const LONG clause_bytes = ImmGetCompositionStringW(context, GCS_COMPCLAUSE, nullptr, 0);
  if (clause_bytes >= static_cast<LONG>(2 * sizeof(uint32_t))) {
    std::vector<uint32_t> clauses(static_cast<size_t>(clause_bytes) / sizeof(uint32_t));
    ImmGetCompositionStringW(context, GCS_COMPCLAUSE, clauses.data(),
                             static_cast<DWORD>(clause_bytes));
    for (size_t i = 0; i + 1 < clauses.size(); ++i) {
      CefCompositionUnderline underline;
      underline.range = CefRange(clauses[i], clauses[i + 1]);
      underline.color = 0xFF000000;
      underline.background_color = 0x00000000;
      underline.thick = 0;
      if (underline.range.from >= target_start && underline.range.to <= target_end) {
        underline.thick = 1;
      }
      underlines.push_back(underline);
    }
  }
  if (underlines.empty() && length > 0) {
    CefCompositionUnderline underline;
    underline.range = CefRange(0, static_cast<uint32_t>(length));
    underline.color = 0xFF000000;
    underline.background_color = 0x00000000;
    underline.thick = 0;
    underlines.push_back(underline);
  }
  return underlines;
}

// Chinese IMEs ignore ImmSetCandidateWindow and position their candidate list
// from the thread caret, so an OSR window needs a real (invisible) caret.
void EnsureSystemCaret(HWND window) {
  if (CreateCaret(window, nullptr, 1, 1)) ShowCaret(window);
}
}

bool SendKeyMessageToCef(CefRefPtr<CefBrowser> browser, HWND window, UINT message,
                         WPARAM wparam, LPARAM lparam) {
  if (!browser) return false;
  auto host = browser->GetHost();
  if (message == WM_SETFOCUS || message == WM_KILLFOCUS) host->SetFocus(message == WM_SETFOCUS);
  if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN || message == WM_KEYUP ||
      message == WM_SYSKEYUP || message == WM_CHAR || message == WM_SYSCHAR) {
    CefKeyEvent key;
    key.type = message == WM_CHAR || message == WM_SYSCHAR ? KEYEVENT_CHAR :
      message == WM_KEYUP || message == WM_SYSKEYUP ? KEYEVENT_KEYUP : KEYEVENT_RAWKEYDOWN;
    key.windows_key_code = static_cast<int>(wparam);
    key.native_key_code = static_cast<int>(lparam);
    key.is_system_key = message == WM_SYSKEYDOWN || message == WM_SYSKEYUP || message == WM_SYSCHAR;
    key.modifiers = Modifiers(wparam, lparam);
    if (key.type == KEYEVENT_CHAR) key.character = key.unmodified_character = static_cast<char16_t>(wparam);
    host->SendKeyEvent(key);
    return true;
  }
  if (message == WM_IME_SETCONTEXT) {
    // CEF draws the composition inline in the page; the IMM default would also
    // pop its own composition window at the window origin.
    DefWindowProcW(window, message, wparam, lparam & ~ISC_SHOWUICOMPOSITIONWINDOW);
    return true;
  }
  if (message == WM_IME_STARTCOMPOSITION) {
    LogImeDebug("STARTCOMPOSITION window=%p\n", window);
    EnsureSystemCaret(window);
    return true;
  }
  if (message == WM_IME_COMPOSITION) {
    HIMC context = ImmGetContext(window);
    LogImeDebug("COMPOSITION window=%p ctx=%p flags=0x%08lX result=%d comp=%d\n", window,
                context, static_cast<unsigned long>(lparam),
                (lparam & GCS_RESULTSTR) ? 1 : 0, (lparam & GCS_COMPSTR) ? 1 : 0);
    if (context) {
      bool committed = false;
      if (lparam & GCS_RESULTSTR) {
        const auto result = DumpComposition(context, GCS_RESULTSTR);
        LogImeDebug("  result %s\n", result.value.c_str());
        host->SetFocus(true);
        // Windowless IME text APIs never reach an out-of-process iframe on
        // CEF 149 (ImeCommitText targets the main frame only; master added
        // GetFocusedWidgetForIme), and every cast page lives in one. Key
        // events are routed to whichever frame has focus in any process, so
        // type the result as characters.
        const std::wstring text = Composition(context, GCS_RESULTSTR);
        for (size_t i = 0; i < text.size(); ++i) {
          const char16_t unit = static_cast<char16_t>(text[i]);
          int code_point = unit;
          if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.size()) {
            // Paired surrogates: ui::KeyEvent::FromCharacter takes the whole
            // char32_t, so send one event carrying the full code point
            // instead of halves that Blink cannot insert on their own.
            const char16_t low = static_cast<char16_t>(text[i + 1]);
            if (low >= 0xDC00 && low <= 0xDFFF) {
              code_point = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
              ++i;
            }
          }
          // CEF 149 rebuilds the inserted character from windows_key_code
          // alone (TranslateUiKeyEvent calls ui::KeyEvent::FromCharacter)
          // and ignores `character`; leaving it at 0 silently drops the text.
          // Same shape as the WM_CHAR path, where wparam is the character.
          CefKeyEvent key;
          key.type = KEYEVENT_CHAR;
          key.windows_key_code = code_point;
          key.character = key.unmodified_character = unit;
          host->SendKeyEvent(key);
          LogImeDebug("  commit cp=%d\n", code_point);
        }
        committed = true;
      }
      if (lparam & GCS_COMPSTR) {
        auto text = Composition(context, GCS_COMPSTR);
        const auto comp = DumpComposition(context, GCS_COMPSTR);
        LONG cursor = ImmGetCompositionStringW(context, GCS_CURSORPOS, nullptr, 0);
        LogImeDebug("  comp %s cursor=%ld\n", comp.value.c_str(), static_cast<long>(cursor));
        cursor = std::clamp(cursor, LONG{0}, static_cast<LONG>(text.size()));
        const auto position = static_cast<uint32_t>(cursor);
        // Selection attributes mark the clause the user picked; thick underline.
        uint32_t target_start = static_cast<uint32_t>(text.size());
        uint32_t target_end = target_start;
        if (lparam & GCS_COMPATTR) {
          const LONG attr_bytes = ImmGetCompositionStringW(context, GCS_COMPATTR, nullptr, 0);
          if (attr_bytes > 0) {
            std::vector<char> attrs(static_cast<size_t>(attr_bytes));
            ImmGetCompositionStringW(context, GCS_COMPATTR, attrs.data(),
                                     static_cast<DWORD>(attr_bytes));
            target_start = 0;
            while (target_start < attrs.size() && !IsSelectionAttribute(attrs[target_start])) {
              ++target_start;
            }
            target_end = target_start;
            while (target_end < attrs.size() && IsSelectionAttribute(attrs[target_end])) {
              ++target_end;
            }
          }
        }
        host->ImeSetComposition(text, CompositionUnderlines(context, text.size(), target_start,
                                                           target_end),
                                CefRange::InvalidRange(), CefRange(position, position));
      } else if (committed) {
        // Result-only message ends the composition; same as the CEF OSR sample.
        host->ImeCancelComposition();
      }
      ImmReleaseContext(window, context);
    }
    return true;
  }
  if (message == WM_IME_ENDCOMPOSITION) {
    LogImeDebug("ENDCOMPOSITION window=%p\n", window);
    host->ImeCancelComposition();
    // Fall through to DefWindowProc so IMM releases its composition resources.
    return false;
  }
  return false;
}

CefKeyboard::CefKeyboard(HWND window) : window_(window) {
  SetWindowSubclass(window_, WindowProc, reinterpret_cast<UINT_PTR>(this), reinterpret_cast<DWORD_PTR>(this));
}
CefKeyboard::~CefKeyboard() {
  SetBrowser(nullptr);
  if (window_) RemoveWindowSubclass(window_, WindowProc, reinterpret_cast<UINT_PTR>(this));
}
void CefKeyboard::SetBrowser(CefRefPtr<CefBrowser> browser) {
  if (browser_ == browser) {
    if (browser_) browser_->GetHost()->SetFocus(true);
    return;
  }
  if (browser_) {
    browser_->GetHost()->ImeCancelComposition();
    browser_->GetHost()->SetFocus(false);
  }
  browser_ = browser;
  if (browser_) browser_->GetHost()->SetFocus(true);
}
LRESULT CALLBACK CefKeyboard::WindowProc(HWND window, UINT message, WPARAM wparam,
                                         LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto* self = reinterpret_cast<CefKeyboard*>(data);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, WindowProc, id);
    self->window_ = nullptr;
  }
  if (!self->browser_) return DefSubclassProc(window, message, wparam, lparam);
  if (SendKeyMessageToCef(self->browser_, window, message, wparam, lparam)) return 0;
  return DefSubclassProc(window, message, wparam, lparam);
}
