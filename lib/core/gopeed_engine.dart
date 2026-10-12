import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Gopeed 下载引擎 Dart 桥接层。
///
/// 通过 MethodChannel「com.liuguang.bdjx/gopeed」启动内嵌 Go 服务，
/// 之后全部走 `http://127.0.0.1:[port]/api/v1` 的 REST API。
///
/// 任务状态机（Gopeed）：ready / running / wait / pause / error / done
class GopeedEngine {
  GopeedEngine._();
  static final GopeedEngine instance = GopeedEngine._();

  static const _channel = MethodChannel('com.liuguang.bdjx/gopeed');
  static const _appId = 'com.liuguang.bdjx';

  int? _port;
  bool _started = false;
  Process? _proc;

  bool get isStarted => _started;
  int? get port => _port;

  /// 启动内嵌服务。幂等：已启动时探测引擎是否仍存活，
  /// 存活则直接返回当前端口，否则复位状态后重新拉起引擎。
  Future<int> start({required String downloadDir, int maxRunning = 3}) async {
    if (_started && _port != null) {
      if (await _isEngineAlive()) return _port!;
      // 引擎进程已死亡/端口不可达（如被误杀、崩溃）：复位后走完整重启路径，
      // 避免后续请求全部命中死端口并报 Connection refused 且永不恢复。
      forceReset();
    }
    final configJson = jsonEncode({
      'network': 'tcp',
      'address': '127.0.0.1:0',
      'refreshInterval': 350,
      'storage': 'bolt',
      'downloadConfig': {
        'downloadDir': downloadDir,
        'maxRunning': maxRunning,
      },
    });
    if (!kIsWeb && Platform.isWindows) {
      await _startWindowsEngine(downloadDir: downloadDir, maxRunning: maxRunning);
    } else {
      // Android / iOS：MethodChannel（Android 桥见 GopeedBridge.kt）
      final port = await _channel.invokeMethod<int>('start', {
        'config': configJson,
      });
      if (port == null) {
        throw const GopeedApiException(0, 'Gopeed 服务启动失败');
      }
      _port = port;
    }
    _started = true;
    return _port!;
  }

  /// Windows 平台：以子进程方式拉起 gopeed-rest.exe 引擎。
  ///
  /// 引擎把随机端口打印到 stdout（`GOPEED_PORT=<port>`），
  /// 之后同样走 127.0.0.1 REST API，与移动端逻辑一致。
  Future<void> _startWindowsEngine({
    required String downloadDir,
    required int maxRunning,
  }) async {
    final exePath = await _findEngineExe();
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final storageDir = p.join(appData, _appId, 'gopeed');

    await _killStrayEngines();
    var port = -1;
    for (var attempt = 0; attempt < 2; attempt++) {
      final proc =
          await _spawnEngine(exePath, storageDir, downloadDir, maxRunning);
      _proc = proc;
      try {
        port = await _waitEnginePort(proc, const Duration(seconds: 20));
      } catch (_) {
        _killEngine(proc);
        rethrow;
      }
      if (port > 0) break;
      _killEngine(proc);
      await _killStrayEngines();
    }
    if (port <= 0) {
      throw const GopeedApiException(0, 'Gopeed 引擎启动超时');
    }
    _port = port;
  }

  Future<Process> _spawnEngine(String exePath, String storageDir,
      String downloadDir, int maxRunning) async {
    return Process.start(exePath, [
      '--storage', storageDir,
      '--download', downloadDir,
      '--max', '$maxRunning',
    ]);
  }

  Future<int> _waitEnginePort(Process proc, Duration timeout) async {
    // 持续消费 stdout/stderr，避免子进程写满管道而阻塞
    final portCompleter = Completer<int>();
    final errCompleter = Completer<String>();
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('GOPEED_PORT=') && !portCompleter.isCompleted) {
        portCompleter.complete(int.tryParse(line.substring(12)) ?? -1);
      } else if (line.startsWith('GOPEED_ERROR=') &&
          !errCompleter.isCompleted) {
        errCompleter.complete(line.substring(13));
      }
    });
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {});
    try {
      return await Future.any<int>([
        portCompleter.future,
        errCompleter.future.then(
            (e) => throw GopeedApiException(0, 'Gopeed 引擎启动失败: $e')),
        proc.exitCode.then(
            (code) => throw GopeedApiException(0, 'Gopeed 引擎意外退出（退出码 $code）')),
      ]).timeout(timeout);
    } on TimeoutException {
      return -1;
    }
  }

  Future<void> _killStrayEngines() async {
    try {
      await Process.run('taskkill', ['/IM', 'gopeed-rest.exe', '/F']);
    } catch (_) {}
  }

  void _killEngine(Process? proc) {
    final p = proc;
    if (p == null) return;
    try {
      p.kill(ProcessSignal.sigkill);
    } catch (_) {}
  }

  Future<String> _findEngineExe() async {
    final candidates = [
      p.join(p.dirname(Platform.resolvedExecutable), 'gopeed-rest.exe'),
      p.join(Directory.current.path, 'gopeed-rest.exe'),
      p.join(Directory.current.path, 'windows', 'runner', 'gopeed-rest.exe'),
      p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner',
          'gopeed-rest.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    throw const GopeedApiException(0, '未找到 gopeed-rest.exe 引擎文件');
  }

  Future<void> stop() async {
    if (!kIsWeb && Platform.isWindows) {
      final proc = _proc;
      _proc = null;
      if (proc != null) {
        proc.kill();
        try {
          await proc.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {
          proc.kill(ProcessSignal.sigkill);
        }
      }
      _started = false;
      _port = null;
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } finally {
      _started = false;
      _port = null;
    }
  }

  Uri _api(String path) {
    final port = _port;
    if (port == null) throw const GopeedApiException(0, 'Gopeed 服务未启动');
    return Uri.parse('http://127.0.0.1:$port/api/v1$path');
  }

  /// 轻量存活探测：能成功拿到任务列表即认为引擎可用。
  Future<bool> _isEngineAlive() async {
    try {
      await _request('GET', '/tasks');
      return true;
    } on GopeedApiException catch (e) {
      // 连接类错误（端口拒绝/超时）视为引擎已死；业务类错误说明引擎可达。
      return !e.isConnectionError;
    } catch (_) {
      return false;
    }
  }

  /// 强制复位引擎状态（引擎进程可能已死）。下次 [start] 会重新拉起引擎。
  void forceReset() {
    _proc = null;
    _started = false;
    _port = null;
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = _api(path).replace(queryParameters: query);
    final req = http.Request(method, uri);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response resp;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      resp = await http.Response.fromStream(streamed);
    } on SocketException catch (e) {
      throw GopeedApiException(-1, 'Gopeed 引擎连接失败: ${e.message}',
          isConnectionError: true);
    } on http.ClientException catch (e) {
      throw GopeedApiException(-1, 'Gopeed 引擎连接失败: ${e.message}',
          isConnectionError: true);
    } on TimeoutException {
      throw const GopeedApiException(-1, 'Gopeed 引擎连接超时',
          isConnectionError: true);
    }
    final text = utf8.decode(resp.bodyBytes);
    final map = text.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(text) as Map<String, dynamic>);
    final code = (map['code'] as num?)?.toInt() ?? -1;
    if (resp.statusCode != 200 || code != 0) {
      throw GopeedApiException(
        resp.statusCode,
        map['msg']?.toString() ?? '请求失败',
      );
    }
    return map['data'];
  }

  /// 创建下载任务，返回 Gopeed 任务 id。
  /// [path] 为目标保存目录（绝对路径），[name] 为文件名。
  /// [headers] 透传 Cookie / UA 等请求头。
  Future<String> createTask({
    required String url,
    required String name,
    required String path,
    int connections = 3,
    Map<String, String> headers = const {},
    String method = 'GET',
  }) async {
    final data = await _request('POST', '/tasks', body: {
      'req': {
        'url': url,
        'extra': {'method': method, 'header': headers},
      },
      'opts': {
        'name': name,
        'path': path,
        'extra': {'connections': connections},
      },
    });
    return data as String;
  }

  /// 查询任务详情（含 status 与 progress）。
  Future<Map<String, dynamic>> task(String id) async {
    final data = await _request('GET', '/tasks/$id');
    return data as Map<String, dynamic>;
  }

  /// 任务列表。
  Future<List<dynamic>> tasks() async {
    final data = await _request('GET', '/tasks');
    return data as List<dynamic>;
  }

  Future<void> pauseTask(String id) async {
    await _request('PUT', '/tasks/$id/pause');
  }

  Future<void> continueTask(String id) async {
    await _request('PUT', '/tasks/$id/continue');
  }

  /// 删除任务。[force] 为 true 时同时删除已下载文件。
  Future<void> deleteTask(String id, {bool force = false}) async {
    await _request(
      'DELETE',
      '/tasks/$id',
      query: force ? {'force': 'true'} : null,
    );
  }
}

class GopeedApiException implements Exception {
  final int statusCode;
  final String message;

  /// 是否为连接层错误（引擎进程死亡 / 端口不可达 / 请求超时）。
  /// 连接类错误意味着引擎可能已死，上层可借此触发引擎自愈重启。
  final bool isConnectionError;

  const GopeedApiException(this.statusCode, this.message,
      {this.isConnectionError = false});

  @override
  String toString() => 'GopeedApiException($statusCode): $message';
}
