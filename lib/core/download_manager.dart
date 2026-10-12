import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'gopeed_engine.dart';
import 'storage_service.dart';

/// 单个下载任务在 UI 中的状态。
enum DownloadStatus {
  ready,
  running,
  waiting,
  paused,
  error,
  done;

  static DownloadStatus fromEngine(String raw) {
    switch (raw) {
      case 'running':
        return DownloadStatus.running;
      case 'wait':
        return DownloadStatus.waiting;
      case 'pause':
        return DownloadStatus.paused;
      case 'error':
        return DownloadStatus.error;
      case 'done':
        return DownloadStatus.done;
      default:
        return DownloadStatus.ready;
    }
  }

  bool get isTerminal => this == DownloadStatus.done || this == DownloadStatus.error;
  bool get isActive => this == DownloadStatus.running || this == DownloadStatus.waiting;

  String get label {
    switch (this) {
      case DownloadStatus.ready:
        return '准备中';
      case DownloadStatus.running:
        return '下载中';
      case DownloadStatus.waiting:
        return '排队中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.error:
        return '失败';
      case DownloadStatus.done:
        return '已完成';
    }
  }
}

/// 一个下载任务（可变，供 UI 直接读取进度）。
class DownloadItem {
  DownloadItem({
    required this.gopeedId,
    required this.name,
    required this.url,
  });

  final String gopeedId;
  final String name;
  final String url;

  DownloadStatus status = DownloadStatus.ready;
  int downloaded = 0;
  int total = 0;
  double speed = 0;
  String? error;

  /// 0.0 ~ 1.0，总大小未知时返回 null（UI 走不确定进度条）。
  double? get progress {
    if (total <= 0) return null;
    final value = downloaded / total;
    return value.clamp(0.0, 1.0);
  }

  String get speedLabel {
    if (speed <= 0) return '';
    final kb = speed / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB/s';
    return '${(kb / 1024).toStringAsFixed(1)} MB/s';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final digits = value >= 100 || index == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[index]}';
  }

  /// 已下载 / 总大小文案。
  String get sizeLabel {
    final done = formatBytes(downloaded);
    if (total <= 0) return done;
    return '$done / ${formatBytes(total)}';
  }
}

/// Gopeed 下载任务管理器。
///
/// 负责：解析下载目录 → 拉起引擎 → 创建/查询/暂停/继续/删除任务，
/// 并以 800ms 轮询把引擎进度同步到 [items]（供 UI 监听刷新）。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final List<DownloadItem> items = <DownloadItem>[];
  final GopeedEngine _engine = GopeedEngine.instance;
  final StorageService _storage = StorageService.instance;

  Timer? _pollTimer;
  bool _engineReady = false;
  String? _downloadDir;

  bool get engineReady => _engineReady;
  String? get downloadDir => _downloadDir;

  /// 用户是否已自定义下载目录。
  bool get isCustomDir => _storage.customDir != null;
  String? get customDir => _storage.customDir;

  /// 解析并缓存下载目录。
  ///
  /// 优先用户自定义目录，其次系统公共下载目录（`/storage/emulated/0/Download/`），
  /// 均不可写时回退到应用专属目录。
  Future<String> _resolveDownloadDir() async {
    if (_downloadDir != null) return _downloadDir!;
    _downloadDir = await _storage.resolveDir();
    return _downloadDir!;
  }

  /// 设置自定义下载目录。成功后立即对新任务生效（无需重启引擎）。
  Future<bool> setDownloadDir(String path) async {
    final ok = await _storage.setCustomDir(path);
    if (ok) {
      _downloadDir = null; // 失效缓存，后续任务使用新目录。
      notifyListeners();
    }
    return ok;
  }

  /// 恢复为系统默认下载目录。
  Future<void> resetDownloadDir() async {
    await _storage.resetDir();
    _downloadDir = null;
    notifyListeners();
  }

  /// 申请存储权限（Android 11+ 跳系统「所有文件访问」设置页）。
  Future<bool> requestStoragePermission() => _storage.requestPermission();

  /// 当前是否已获得存储权限。
  Future<bool> hasStoragePermission() => _storage.hasPermission();

  /// 获取当前生效的下载目录（必要时触发解析）。
  Future<String> effectiveDir() => _resolveDownloadDir();

  /// 确保引擎已启动（含失效自愈）。
  Future<void> _ensureEngine() async {
    if (_engineReady && _engine.isStarted) return;
    final dir = await _resolveDownloadDir();
    await _engine.start(downloadDir: dir, maxRunning: 3);
    _engineReady = true;
  }

  /// 从引擎恢复既有任务（App 重启后 bolt 库中的历史任务）。
  Future<void> restore() async {
    try {
      await _ensureEngine();
      final list = await _engine.tasks();
      items
        ..clear()
        ..addAll(list.whereType<Map<String, dynamic>>().map(_fromEngineJson));
      if (items.isNotEmpty) _startPolling();
      notifyListeners();
    } catch (_) {
      // 恢复失败不影响后续新建任务。
    }
  }

  DownloadItem _fromEngineJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final name = (json['meta']?['name']?.toString()) ??
        (json['name']?.toString() ?? '未命名');
    final url = json['meta']?['req']?['url']?.toString() ?? '';
    final item = DownloadItem(gopeedId: id, name: name, url: url);
    _applyEngineState(item, json);
    return item;
  }

  void _applyEngineState(DownloadItem item, Map<String, dynamic> json) {
    item.status = DownloadStatus.fromEngine(json['status']?.toString() ?? '');
    final progress = json['progress'] as Map<String, dynamic>? ?? const {};
    item.downloaded = (progress['downloaded'] as num?)?.toInt() ?? 0;
    item.speed = (progress['speed'] as num?)?.toDouble() ?? 0;
    final size = (json['meta']?['res']?['size'] as num?)?.toInt() ?? 0;
    if (size > 0) item.total = size;
    final err = json['error']?.toString();
    item.error = (err == null || err.isEmpty) ? null : err;
  }

  /// 新建下载任务。返回创建出的 [DownloadItem]。
  Future<DownloadItem> download({required String url, String? name}) async {
    await _ensureEngine();
    final dir = await _resolveDownloadDir();
    final fileName = _fileNameFrom(url, name);

    var engineRetried = false;
    while (true) {
      try {
        final id = await _engine.createTask(
          url: url,
          name: fileName,
          path: dir,
          connections: 3,
        );
        final item =
            DownloadItem(gopeedId: id, name: fileName, url: url)
              ..status = DownloadStatus.running;
        items.insert(0, item);
        notifyListeners();
        _startPolling();
        return item;
      } catch (e) {
        final isConn = (e is GopeedApiException && e.isConnectionError) ||
            e is SocketException;
        if (isConn && !engineRetried) {
          // 引擎进程已死：复位并重启后重试一次。
          engineRetried = true;
          _engineReady = false;
          _engine.forceReset();
          await _ensureEngine();
          continue;
        }
        rethrow;
      }
    }
  }

  /// 由链接推导文件名；无有效路径段时用时间戳兜底。
  String _fileNameFrom(String url, String? name) {
    if (name != null && name.trim().isNotEmpty) return name.trim();
    // 百度直链把真实文件名放在 `outname=` 查询参数里，路径段只是文件 id。
    final outname = RegExp(r'[?&]outname=([^&]+)').firstMatch(url);
    if (outname != null) {
      final decoded = Uri.decodeComponent(outname.group(1)!.replaceAll('+', ' '));
      if (decoded.trim().isNotEmpty) return decoded.trim();
    }
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.isNotEmpty) {
        final last = Uri.decodeComponent(segments.last);
        if (last.trim().isNotEmpty) return last.trim();
      }
    } catch (_) {
      // 忽略解析失败，走兜底。
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _pollTasks(),
    );
  }

  Future<void> _pollTasks() async {
    final active = items.where((e) => !e.status.isTerminal).toList();
    if (active.isEmpty) {
      _stopPolling();
      return;
    }
    for (final item in active) {
      try {
        final data = await _engine.task(item.gopeedId);
        _applyEngineState(item, data);
      } on GopeedApiException catch (e) {
        if (e.isConnectionError) {
          _engineReady = false;
          item.error = '下载引擎连接中断';
        } else {
          item.status = DownloadStatus.error;
          item.error = e.message;
        }
      } catch (e) {
        item.error = '$e';
      }
    }
    notifyListeners();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> pause(String id) async {
    await _engine.pauseTask(id);
    _scheduleRefresh();
  }

  Future<void> resume(String id) async {
    await _ensureEngine();
    await _engine.continueTask(id);
    _scheduleRefresh();
  }

  /// 删除任务。[deleteFile] 为 true 时同时删除已下载的文件。
  Future<void> remove(String id, {bool deleteFile = false}) async {
    try {
      await _engine.deleteTask(id, force: deleteFile);
    } catch (_) {
      // 引擎任务可能已不存在，仅移除本地记录。
    }
    items.removeWhere((e) => e.gopeedId == id);
    notifyListeners();
  }

  void _scheduleRefresh() {
    _startPolling();
    unawaited(_pollTasks());
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
