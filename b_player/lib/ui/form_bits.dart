import 'package:flutter/material.dart';

import '../theme.dart';

/// 设置页里反复用到的小表单件：字段标题、选项胶囊、输入框。
///
/// 原来是「音源」面板和「设置」弹窗各写一份，投放面板是第三份，所以收到这里统一。

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: 11, color: C.faint, fontWeight: FontWeight.w600, letterSpacing: .5));
}

class Choice extends StatelessWidget {
  const Choice({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.fill,
    this.compact = false,
  });
  final String label;
  final bool on;
  final VoidCallback onTap;

  /// 未选中时的底色；弹窗底色偏深时可以覆盖，否则胶囊会“陷”进背景里。
  final Color? fill;

  /// 一行里要塞很多项时用更窄的内边距。
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
        color: on ? C.acc.withValues(alpha: .14) : (fill ?? C.panel2),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 14, vertical: compact ? 6 : 8),
            decoration: BoxDecoration(
              border: Border.all(color: on ? C.acc : C.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? C.acc : C.dim,
                )),
          ),
        ),
      );
}

class FormInput extends StatelessWidget {
  const FormInput({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.suffix,
    this.maxLines = 1,
    this.obscureText = false,
  });
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final int maxLines;
  final bool obscureText;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: maxLines,
        obscureText: obscureText,
        style: TextStyle(fontSize: 12.5, color: C.txt),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: C.panel2,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: C.faint),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: C.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: C.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: C.acc),
          ),
        ),
      );
}
