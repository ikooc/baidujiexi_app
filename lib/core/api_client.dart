/// Upstream convert-API client.
///
/// Flow:
///  1. `GET /api/session`        → `{token, secret, ttl}`
///  2. `POST /api/downloadConvertUrl` (SSE) → progressive `data:` frames
///
/// Every request must carry the site `Origin`/`Referer`; sensitive POSTs also
/// carry `x-session-token` plus `x-client-sign`, where the signature is
/// computed over the *share link string* (not the JSON body).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crypto.dart';
import 'models.dart';
import 'remote_config.dart';

/// Normalises a pasted Baidu share blob into the canonical form the upstream
/// expects: `https://pan.baidu.com/s/1<surl>?pwd=<code>`.
///
/// The extraction code may live either in the URL (`?pwd=`) or anywhere else
/// in the pasted text (e.g. `提取码：vD32`). Returns the input unchanged when no
/// Baidu share link can be recognised.
String normalizeShareLink(String raw) {
  final text = raw.trim();
  var surl = '';
  final canonical = RegExp(r'https?://pan\.baidu\.com/s/1([A-Za-z0-9_-]+)')
      .firstMatch(text);
  if (canonical != null) {
    surl = canonical.group(1)!;
  } else {
    final wap = RegExp(
      r'https?://pan\.baidu\.com/wap/init/?\?[^\s]*?surl=([A-Za-z0-9_-]+)',
    ).firstMatch(text);
    if (wap != null) surl = wap.group(1)!;
  }
  if (surl.isEmpty) return text;

  var link = 'https://pan.baidu.com/s/1$surl';
  final inUrl = RegExp(r'[?&]pwd=([^&\s]+)').firstMatch(text);
  final pwd = inUrl?.group(1) ?? _pwdFromText(text);
  if (pwd.isNotEmpty) link = '$link?pwd=$pwd';
  return link;
}

/// Extracts a 4-char extraction code from free text such as `提取码：vD32`.
String _pwdFromText(String text) {
  final match = RegExp(
    r'(?:提取码|访问码|密码|pwd)\s*[:：=]?\s*([A-Za-z0-9]{4})(?![A-Za-z0-9])',
  ).firstMatch(text);
  return match?.group(1) ?? '';
}

/// Client for the upstream "convert share link → direct download URL" service.
class ConvertApiClient {
  ConvertApiClient(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;

  ApiSession? _session;

  /// Seconds to wait before a session is considered stale, leaving headroom
  /// so a request never starts with an almost-expired token.
  static const Duration _sessionSafetyMargin = Duration(minutes: 1);

  DateTime? _sessionObtainedAt;

  /// Returns a usable session, fetching a fresh one if needed.
  Future<ApiSession> ensureSession({bool forceRefresh = false}) async {
    final current = _session;
    if (!forceRefresh &&
        current != null &&
        current.isValid &&
        _sessionObtainedAt != null &&
        DateTime.now().difference(_sessionObtainedAt!) <
            Duration(milliseconds: current.ttl) - _sessionSafetyMargin) {
      return current;
    }

    final session = await _createSession();
    _session = session;
    _sessionObtainedAt = DateTime.now();
    return session;
  }

  Future<ApiSession> _createSession() async {
    return _withFallback<ApiSession>((base) async {
      final response = await _client.get(
        Uri.parse('$base/api/session'),
        headers: _baseHeaders(),
      ).timeout(const Duration(seconds: 12));

      final json = _decodeJson(response);
      if (response.statusCode != 200) {
        throw ApiException(
          _messageFrom(json) ?? '获取会话失败（${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final session = ApiSession.fromJson(json);
      if (!session.isValid) {
        throw ApiException('会话响应缺少 token/secret');
      }
      return session;
    });
  }

  /// Starts a convert task and emits [ConvertEvent] frames as they arrive.
  ///
  /// The caller should `await for` the returned stream and update the UI on
  /// each frame. Errors surface as [ApiException] on the stream.
  Stream<ConvertEvent> convert(String link, {String? mode}) async* {
    final normalizedLink = normalizeShareLink(link);
    if (normalizedLink.isEmpty) {
      throw ApiException('请输入分享链接');
    }

    final session = await ensureSession();
    final resolvedMode = mode ?? config.defaultMode;
    final sign = clientSign(session.secret, normalizedLink);
    final body = jsonEncode(<String, dynamic>{
      'link': normalizedLink,
      'mode': resolvedMode,
      'ref': config.referer,
    });

    Object? lastError;
    for (final base in config.allBases) {
      try {
        yield* _convertOn(base, session, sign, body);
        return;
      } on ApiException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    throw ApiException('转换请求失败：${lastError ?? '未知错误'}');
  }

  Stream<ConvertEvent> _convertOn(
    String base,
    ApiSession session,
    String sign,
    String body,
  ) async* {
    final request = http.Request('POST', Uri.parse('$base/api/downloadConvertUrl'))
      ..headers.addAll(<String, String>{
        ..._baseHeaders(),
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'x-session-token': session.token,
        'x-client-sign': sign,
      })
      ..body = body;

    final response = await _client.send(request);

    if (response.statusCode == 401 || response.statusCode == 403) {
      // Session may have expired or origin rejected us; force a refresh on
      // the next call.
      _session = null;
      final text = await response.stream.bytesToString();
      throw ApiException(
        _messageFromRaw(text) ?? '请求被拒绝（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 429) {
      throw ApiException('操作过于频繁，请稍后再试', statusCode: 429);
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      throw ApiException(
        _messageFromRaw(text) ?? '转换失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }

    yield* _parseSse(response.stream);
  }

  /// Decodes a `text/event-stream` body into [ConvertEvent] frames.
  Stream<ConvertEvent> _parseSse(http.ByteStream stream) async* {
    final buffer = StringBuffer();

    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      var content = buffer.toString();
      var newlineIndex = content.indexOf('\n');

      while (newlineIndex != -1) {
        final line = content.substring(0, newlineIndex).trimRight();
        content = content.substring(newlineIndex + 1);

        final event = _decodeSseLine(line);
        if (event != null) {
          yield event;
          if (event.step == 'done' || event.isError) {
            return;
          }
        }
        newlineIndex = content.indexOf('\n');
      }

      buffer
        ..clear()
        ..write(content);
    }

    // Flush any trailing frame that lacked a terminating newline.
    final tail = _decodeSseLine(buffer.toString().trim());
    if (tail != null) yield tail;
  }

  ConvertEvent? _decodeSseLine(String line) {
    if (line.isEmpty || line.startsWith(':')) return null;
    if (!line.startsWith('data:')) return null;

    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final step = (decoded['step'] ?? '').toString();
      return ConvertEvent(step: step, data: decoded);
    } catch (_) {
      return null;
    }
  }

  /// Aggregates a whole convert run into a single [ConvertResult].
  ///
  /// [onEvent] receives every raw frame so the UI can show progress.
  Future<ConvertResult> convertToResult(
    String link, {
    String? mode,
    void Function(ConvertEvent event)? onEvent,
  }) async {
    final result = ConvertResult();

    await for (final event in convert(link, mode: mode)) {
      onEvent?.call(event);
      if (event.isError) {
        throw ApiException(event.message ?? '转换失败');
      }

      _collect(event.data['downloadLinks'], result.links);
      _collect(event.data['exeUrl'], result.exeUrls);
      _collect(event.data['exeUrls'], result.exeUrls);
      _collect(event.data['tokens'], result.tokens);
      _collect(event.data['downloadLink'], result.links);
    }

    return result;
  }

  void _collect(dynamic value, List<String> target) {
    if (value == null) return;
    if (value is String) {
      if (value.isNotEmpty && !target.contains(value)) target.add(value);
      return;
    }
    if (value is List) {
      for (final item in value) {
        _collect(item, target);
      }
    }
  }

  Map<String, String> _baseHeaders() => <String, String>{
        'Origin': config.siteOrigin,
        'Referer': config.referer,
        'User-Agent': 'BaidujiexiApp/1.0 (Flutter)',
      };

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    } catch (_) {
      // fall through
    }
    return <String, dynamic>{};
  }

  String? _messageFrom(Map<String, dynamic> json) {
    final msg = json['msg'] ?? json['message'] ?? json['error'];
    return msg is String && msg.isNotEmpty ? msg : null;
  }

  String? _messageFromRaw(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return _messageFrom(decoded);
    } catch (_) {
      // not JSON
    }
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Runs [action] against the primary base, then each fallback in order.
  Future<T> _withFallback<T>(Future<T> Function(String base) action) async {
    Object? lastError;
    for (final base in config.allBases) {
      try {
        return await action(base);
      } on ApiException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    throw ApiException('网络请求失败：${lastError ?? '未知错误'}');
  }

  void dispose() {
    _client.close();
  }
}
