import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/l10n.dart';

/// 直接按路径扫描目录、读同名 `.lrc`，需要「所有文件访问」；
/// 只有音频权限时能读音频文件，但列目录/读歌词仍会失败。
class StoragePermissionState {
  const StoragePermissionState({
    this.isAndroid = false,
    this.sdkInt = 0,
    this.audio = false,
    this.allFiles = false,
  });

  final bool isAndroid;
  final int sdkInt;
  final bool audio;
  final bool allFiles;

  bool get canReadLibrary => !isAndroid || allFiles;

  String get summary {
    if (!isAndroid) return l10n.permNoPermissionNeeded;
    if (allFiles) return l10n.permAllFiles;
    if (audio) return l10n.permAudioOnly;
    return l10n.permNotGranted;
  }
}

abstract final class LibraryPermissions {
  static Future<StoragePermissionState> check() async {
    if (!Platform.isAndroid) return const StoragePermissionState();
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final audio = sdk >= 33
          ? await Permission.audio.isGranted
          : await Permission.storage.isGranted;
      final all = await Permission.manageExternalStorage.isGranted;
      return StoragePermissionState(isAndroid: true, sdkInt: sdk, audio: audio, allFiles: all);
    } catch (_) {
      return const StoragePermissionState(isAndroid: true);
    }
  }

  /// 请求权限。Android 11+ 的“所有文件访问”会跳到系统设置页，返回后重新检查。
  static Future<StoragePermissionState> request() async {
    if (!Platform.isAndroid) return const StoragePermissionState();
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= 33) {
        if (!await Permission.audio.isGranted) await Permission.audio.request();
      } else if (!await Permission.storage.isGranted) {
        await Permission.storage.request();
      }
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    } catch (_) {
      // 插件不可用（例如桌面端误调用）时退回只读检查。
    }
    return check();
  }

  static Future<bool> openSystemSettings() => openAppSettings();
}
