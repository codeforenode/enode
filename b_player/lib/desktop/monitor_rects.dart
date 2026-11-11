/// 用 user32 直接读显示器的**物理像素**矩形（rcMonitor / rcWork）。
///
/// 为什么需要它：screen_retriever 报的是「除以了缩放系数」的逻辑像素，而画布
/// presenter 的 `CreateWindowExW` 在 PerMonitorV2 进程里吃的是物理像素——两套
/// 单位只在 100% 缩放时相等，混用必投错屏。另外 screen_retriever 拿不到
/// rcMonitor 原点（它的 fullSize 是「显示器右/下沿 − 工作区左/上沿」），任务栏
/// 在顶部时全屏投放会整体偏一截。MONITORINFO 一并给全这两个问题。
///
/// 只在 Windows 上可用；其余平台返回空表，调用方走回退换算。
library;

import 'dart:ffi';
import 'dart:ui' show Rect;

import 'package:ffi/ffi.dart';

final class _MonitorInfoExW extends Struct {
  @Uint32()
  external int cbSize;

  @Int32()
  external int monLeft;
  @Int32()
  external int monTop;
  @Int32()
  external int monRight;
  @Int32()
  external int monBottom;

  @Int32()
  external int workLeft;
  @Int32()
  external int workTop;
  @Int32()
  external int workRight;
  @Int32()
  external int workBottom;

  @Uint32()
  external int dwFlags;

  // WCHAR szDevice[32]：设备名（\\.\DISPLAY1 风格），按 UTF-16 手工解码。
  @Array.multi([32])
  external Array<Uint16> szDevice;
}

typedef _EnumDisplayMonitorsNative = Int32 Function(
    IntPtr hdc, IntPtr clip, Pointer<NativeFunction<_MonitorEnumProcNative>> proc, IntPtr lParam);
typedef _EnumDisplayMonitorsDart = int Function(
    int hdc, int clip, Pointer<NativeFunction<_MonitorEnumProcNative>> proc, int lParam);
typedef _MonitorEnumProcNative = Int32 Function(
    IntPtr hdc, IntPtr hMonitor, Pointer<Void> lprcMonitor, IntPtr lParam);
typedef _GetMonitorInfoNative = Int32 Function(IntPtr hMonitor, Pointer<_MonitorInfoExW> lpmi);
typedef _GetMonitorInfoDart = int Function(int hMonitor, Pointer<_MonitorInfoExW> lpmi);

final List<Rect> _monitorRects = [];
final List<Rect> _workRects = [];

int _collectMonitor(int hdc, int hMonitor, Pointer<Void> lprcMonitor, int lParam) {
  final info = calloc<_MonitorInfoExW>();
  try {
    info.ref.cbSize = sizeOf<_MonitorInfoExW>();
    final getMonitorInfo = _getMonitorInfo();
    if (getMonitorInfo(hMonitor, info) == 0) return 1;
    _monitorRects.add(Rect.fromLTRB(
        info.ref.monLeft.toDouble(),
        info.ref.monTop.toDouble(),
        info.ref.monRight.toDouble(),
        info.ref.monBottom.toDouble()));
    _workRects.add(Rect.fromLTRB(
        info.ref.workLeft.toDouble(),
        info.ref.workTop.toDouble(),
        info.ref.workRight.toDouble(),
        info.ref.workBottom.toDouble()));
    return 1;
  } finally {
    calloc.free(info);
  }
}

final Pointer<NativeFunction<_MonitorEnumProcNative>> _enumProc =
    Pointer.fromFunction(_collectMonitor, 0);_GetMonitorInfoDart? _getMonitorInfoCache;
_GetMonitorInfoDart _getMonitorInfo() {
  return _getMonitorInfoCache ??= DynamicLibrary.open('user32.dll')
      .lookupFunction<_GetMonitorInfoNative, _GetMonitorInfoDart>('GetMonitorInfoW');
}

class PhysicalMonitorRects {
  const PhysicalMonitorRects(this.monitor, this.work);

  /// 整个显示器的物理矩形（含任务栏）。
  final Rect monitor;

  /// 工作区的物理矩形。
  final Rect work;
}

List<PhysicalMonitorRects> physicalMonitorRects() {
  _monitorRects.clear();
  _workRects.clear();
  try {
    final enumDisplayMonitors = DynamicLibrary.open('user32.dll')
        .lookupFunction<_EnumDisplayMonitorsNative, _EnumDisplayMonitorsDart>(
            'EnumDisplayMonitors');
    enumDisplayMonitors(0 /*nullptr hdc: 全部显示器*/, 0, _enumProc, 0);
  } catch (_) {
    // 拿不到就回退：调用方用「逻辑 × 缩放」换算。
    return const [];
  }
  return [
    for (var i = 0; i < _monitorRects.length; i++)
      PhysicalMonitorRects(_monitorRects[i], _workRects[i]),
  ];
}

/// 按预测的物理工作区矩形，把 [CastMonitor 索引] 对到物理矩形上。
///
/// screen_retriever 的逻辑坐标 = 物理坐标 / 该屏缩放，所以「工作区左上角 × 缩放」
/// 应与原生 rcWork 一致（±2px 取整误差）。几何完全相同的双屏靠原点区分。
PhysicalMonitorRects? matchPhysicalRect(
    {required Rect predictedWork, required List<PhysicalMonitorRects> all}) {
  const tolerance = 3.0;
  for (final m in all) {
    if ((m.work.left - predictedWork.left).abs() <= tolerance &&
        (m.work.top - predictedWork.top).abs() <= tolerance &&
        (m.work.right - predictedWork.right).abs() <= tolerance &&
        (m.work.bottom - predictedWork.bottom).abs() <= tolerance) {
      return m;
    }
  }
  return null;
}
