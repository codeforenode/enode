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

/// MONITORINFOF_PRIMARY。
const _monitorInfoPrimary = 0x1;

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

/// DISPLAY_DEVICEW。只要 DeviceString（显示器型号），后面的字段不能省——
/// 结构体小了 API 会写到分配区外。
final class _DisplayDeviceW extends Struct {
  @Uint32()
  external int cb;

  @Array.multi([32])
  external Array<Uint16> deviceName;

  @Array.multi([128])
  external Array<Uint16> deviceString;

  @Uint32()
  external int stateFlags;

  @Array.multi([128])
  external Array<Uint16> deviceId;

  @Array.multi([128])
  external Array<Uint16> deviceKey;
}

typedef _EnumDisplayDevicesNative = Int32 Function(
    Pointer<Utf16> lpDevice, Uint32 iDevNum, Pointer<_DisplayDeviceW> lpDisplayDevice, Uint32 dwFlags);
typedef _EnumDisplayDevicesDart = int Function(
    Pointer<Utf16> lpDevice, int iDevNum, Pointer<_DisplayDeviceW> lpDisplayDevice, int dwFlags);

final List<Rect> _monitorRects = [];
final List<Rect> _workRects = [];
final List<bool> _primaryFlags = [];
final List<String> _deviceNames = [];

// MonitorEnumProc 的参数顺序是 (hMonitor, hdcMonitor, lprcMonitor, lpData)；
// 前两个都是句柄，位置写反不会报错，只会让 GetMonitorInfo 失败、静默回退到逻辑坐标。
int _collectMonitor(int hMonitor, int hdcMonitor, Pointer<Void> lprcMonitor, int lParam) {
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
    _primaryFlags.add(info.ref.dwFlags & _monitorInfoPrimary != 0);
    _deviceNames.add(_utf16(info.ref.szDevice, 32));
    return 1;
  } finally {
    calloc.free(info);
  }
}

String _utf16(Array<Uint16> chars, int max) {
  final sb = StringBuffer();
  for (var i = 0; i < max; i++) {
    final c = chars[i];
    if (c == 0) break;
    sb.writeCharCode(c);
  }
  return sb.toString();
}

/// 显示器型号：先问 EDID 解析出来的名字（「DELL U2415」），驱动不报时是
/// 「Generic PnP Monitor」——Windows 没有可靠的「内置屏 / 外接屏」标志，只能这么标识。
String _monitorModel(String deviceName, _EnumDisplayDevicesDart? enumDevices) {
  if (deviceName.isEmpty || enumDevices == null) return '';
  final name = deviceName.toNativeUtf16();
  final dd = calloc<_DisplayDeviceW>();
  try {
    dd.ref.cb = sizeOf<_DisplayDeviceW>();
    if (enumDevices(name, 0, dd, 0) == 0) return '';
    return _utf16(dd.ref.deviceString, 128);
  } catch (_) {
    return '';
  } finally {
    calloc.free(dd);
    malloc.free(name);
  }
}

final Pointer<NativeFunction<_MonitorEnumProcNative>> _enumProc =
    Pointer.fromFunction(_collectMonitor, 0);_GetMonitorInfoDart? _getMonitorInfoCache;
_GetMonitorInfoDart _getMonitorInfo() {
  return _getMonitorInfoCache ??= DynamicLibrary.open('user32.dll')
      .lookupFunction<_GetMonitorInfoNative, _GetMonitorInfoDart>('GetMonitorInfoW');
}

class PhysicalMonitorRects {
  const PhysicalMonitorRects(this.monitor, this.work,
      {this.primary = false, this.device = '', this.model = ''});

  /// 整个显示器的物理矩形（含任务栏）。
  final Rect monitor;

  /// 工作区的物理矩形。
  final Rect work;

  /// 是不是 Windows 的「主显示器」（任务栏默认所在的那块）。
  final bool primary;

  /// GDI 设备名，如 `\\.\DISPLAY1`。
  final String device;

  /// EDID 型号串；驱动不报时为 `Generic PnP Monitor`，取不到时为空。
  final String model;
}

List<PhysicalMonitorRects> physicalMonitorRects() {
  _monitorRects.clear();
  _workRects.clear();
  _primaryFlags.clear();
  _deviceNames.clear();
  try {
    final enumDisplayMonitors = DynamicLibrary.open('user32.dll')
        .lookupFunction<_EnumDisplayMonitorsNative, _EnumDisplayMonitorsDart>(
            'EnumDisplayMonitors');
    enumDisplayMonitors(0 /*nullptr hdc: 全部显示器*/, 0, _enumProc, 0);
  } catch (_) {
    // 拿不到就回退：调用方用「逻辑 × 缩放」换算。
    return const [];
  }
  _EnumDisplayDevicesDart? enumDevices;
  try {
    enumDevices = DynamicLibrary.open('user32.dll')
        .lookupFunction<_EnumDisplayDevicesNative, _EnumDisplayDevicesDart>('EnumDisplayDevicesW');
  } catch (_) {
    enumDevices = null;
  }
  return [
    for (var i = 0; i < _monitorRects.length; i++)
      PhysicalMonitorRects(_monitorRects[i], _workRects[i],
          primary: _primaryFlags[i],
          device: _deviceNames[i],
          model: _monitorModel(_deviceNames[i], enumDevices)),
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
