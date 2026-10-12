import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载目录解析与持久化服务。
///
/// 目录优先级：
///   1. 用户自定义目录（[setCustomDir] 持久化，可写时生效）
///   2. 系统公共下载目录 `/storage/emulated/0/Download/`（Android）
///   3. 应用专属外部目录（无存储权限时的兜底，始终可写）
///
/// Android 7-16 的权限差异由原生 [StorageBridge] 处理，本类只负责编排。
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const MethodChannel _channel =
      MethodChannel('com.liuguang.bdjx/storage');
  static const String _customDirKey = 'download_dir_custom';

  String? _customDir;
  bool _loaded = false;

  /// 用户自定义的下载目录；未设置时为 null。
  String? get customDir => _customDir;

  Future<void> _load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString(_customDirKey);
    _customDir = (dir != null && dir.trim().isNotEmpty) ? dir.trim() : null;
    _loaded = true;
  }

  /// 系统默认下载目录。
  Future<String> defaultDir() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (Platform.isAndroid) {
        try {
          final dir = await _channel.invokeMethod<String>('getDefaultDir');
          if (dir != null && dir.isNotEmpty) return dir;
        } catch (_) {
          // 原生桥不可用时退回应用专属目录。
        }
      }
      return _fallbackDir();
    }
    String? dir;
    try {
      dir = (await getDownloadsDirectory())?.path;
    } catch (_) {
      dir = null;
    }
    return dir ?? _fallbackDir();
  }

  /// 应用专属兜底目录（无需存储权限，永远可写）。
  Future<String> _fallbackDir() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final dir = await _channel.invokeMethod<String>('getFallbackDir');
        if (dir != null && dir.isNotEmpty) return dir;
      } catch (_) {
        // 忽略，走 path_provider 兜底。
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'BaidujiexiDownloads');
  }

  /// 解析当前生效的下载目录，并确保其存在且可写。
  ///
  /// 自定义目录或公共目录不可写时，自动回退到应用专属目录。
  Future<String> resolveDir() async {
    await _load();
    if (_customDir != null && await _isWritable(_customDir!)) {
      return _customDir!;
    }
    final def = await defaultDir();
    if (await _isWritable(def)) return def;
    final fallback = await _fallbackDir();
    await _ensureDir(fallback);
    return fallback;
  }

  /// 设置自定义下载目录。返回是否设置成功（目录存在且可写）。
  Future<bool> setCustomDir(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    if (!await _isWritable(trimmed)) return false;
    await _load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customDirKey, trimmed);
    _customDir = trimmed;
    return true;
  }

  /// 清除自定义目录，恢复使用系统默认下载目录。
  Future<void> resetDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customDirKey);
    _customDir = null;
    _loaded = true;
  }

  /// 当前是否已获得存储权限（Android 11+ 指「所有文件访问」）。
  Future<bool> hasPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 申请存储权限。Android 11+ 会跳转系统设置页，需用户返回后再查询。
  Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isWritable(String path) async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) {
      return _ensureDir(path);
    }
    try {
      return await _channel.invokeMethod<bool>('ensureDir', {'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureDir(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(p.join(path, '.bdjx_write_probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
