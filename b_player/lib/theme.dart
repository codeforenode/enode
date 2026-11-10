import 'package:flutter/material.dart';

/// 与 C端 H5 同一套绿色主色；暗/亮两套色板按当前 Brightness 切换。
/// 色值在每帧构建前由 [C.use] 写入，界面统一引用 `C.*`。
abstract final class C {
  static Color bg = _dark.bg;
  static Color panel = _dark.panel;
  static Color panel2 = _dark.panel2;
  static Color side = _dark.side;
  static Color top = _dark.top;
  static Color line = _dark.line;
  static Color txt = _dark.txt;
  static Color dim = _dark.dim;
  static Color faint = _dark.faint;
  static Color acc = _dark.acc;
  static Color acc2 = _dark.acc2;
  static Color onAcc = _dark.onAcc;
  static Color warn = _dark.warn;
  static Color bad = _dark.bad;
  static Color info = _dark.info;

  static void use(Brightness brightness) {
    final p = brightness == Brightness.dark ? _dark : _light;
    bg = p.bg;
    panel = p.panel;
    panel2 = p.panel2;
    side = p.side;
    top = p.top;
    line = p.line;
    txt = p.txt;
    dim = p.dim;
    faint = p.faint;
    acc = p.acc;
    acc2 = p.acc2;
    onAcc = p.onAcc;
    warn = p.warn;
    bad = p.bad;
    info = p.info;
  }
}

class _Palette {
  const _Palette({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.side,
    required this.top,
    required this.line,
    required this.txt,
    required this.dim,
    required this.faint,
    required this.acc,
    required this.acc2,
    required this.onAcc,
    required this.warn,
    required this.bad,
    required this.info,
  });

  final Color bg;
  final Color panel;
  final Color panel2;
  final Color side;
  final Color top;
  final Color line;
  final Color txt;
  final Color dim;
  final Color faint;
  final Color acc;
  final Color acc2;
  final Color onAcc;
  final Color warn;
  final Color bad;
  final Color info;
}

const _dark = _Palette(
  bg: Color(0xFF0B0E10),
  panel: Color(0xFF14181C),
  panel2: Color(0xFF1A1F24),
  side: Color(0xFF0D1114),
  top: Color(0xFF0E1215),
  line: Color(0xFF262D34),
  txt: Color(0xFFE8EDF1),
  dim: Color(0xFF8B979F),
  faint: Color(0xFF5D6970),
  acc: Color(0xFF3DDC84),
  acc2: Color(0xFF2BB96D),
  onAcc: Color(0xFF06210F),
  warn: Color(0xFFF5A524),
  bad: Color(0xFFF2555A),
  info: Color(0xFF4AA8FF),
);

const _light = _Palette(
  bg: Color(0xFFF4F6F7),
  panel: Color(0xFFFFFFFF),
  panel2: Color(0xFFEDF1F3),
  side: Color(0xFFEBEFF1),
  top: Color(0xFFFFFFFF),
  line: Color(0xFFDCE3E7),
  txt: Color(0xFF1B2227),
  dim: Color(0xFF5A6A73),
  faint: Color(0xFF85949D),
  acc: Color(0xFF12A15A),
  acc2: Color(0xFF0C7F47),
  onAcc: Color(0xFFFFFFFF),
  warn: Color(0xFFB26A00),
  bad: Color(0xFFD2373C),
  info: Color(0xFF1E7FD6),
);

TextStyle get kCardTitle =>
    TextStyle(fontSize: 12, color: C.faint, fontWeight: FontWeight.w600, letterSpacing: .6);
TextStyle get kMini => TextStyle(fontSize: 11, color: C.faint);
const kNums = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Material 桌面端默认用 `adaptiveClickable`——非 Web 平台解析成普通箭头，
/// 所以这里显式指定手形；禁用态仍回落到箭头。
const _clickCursor = WidgetStateMouseCursor.clickable;

ButtonStyle get _cursorButtonStyle => ButtonStyle(mouseCursor: _clickCursor);

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: C.acc,
        onPrimary: C.onAcc,
        secondary: C.acc2,
        onSecondary: Colors.white,
        error: C.bad,
        onError: Colors.white,
        surface: C.panel,
        onSurface: C.txt,
      ),
      textButtonTheme: TextButtonThemeData(style: _cursorButtonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _cursorButtonStyle),
      filledButtonTheme: FilledButtonThemeData(style: _cursorButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _cursorButtonStyle),
      iconButtonTheme: IconButtonThemeData(style: _cursorButtonStyle),
      checkboxTheme: CheckboxThemeData(mouseCursor: _clickCursor),
      radioTheme: RadioThemeData(mouseCursor: _clickCursor),
      switchTheme: SwitchThemeData(mouseCursor: _clickCursor),
    );
