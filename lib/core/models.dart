/// Data models shared between the API client and the UI layer.
library;

/// A short-lived credential pair returned by `/api/session`.
///
/// [secret] is never sent upstream directly; it is only used locally to
/// compute request signatures.
class ApiSession {
  const ApiSession({
    required this.token,
    required this.secret,
    required this.ttl,
  });

  final String token;
  final String secret;

  /// Lifetime in milliseconds as reported by the server (default 30 min).
  final int ttl;

  DateTime get expiresAt => DateTime.now().add(Duration(milliseconds: ttl));

  factory ApiSession.fromJson(Map<String, dynamic> json) {
    return ApiSession(
      token: (json['token'] ?? '').toString(),
      secret: (json['secret'] ?? '').toString(),
      ttl: (json['ttl'] as num?)?.toInt() ?? 1800000,
    );
  }

  bool get isValid => token.isNotEmpty && secret.isNotEmpty;
}

/// Progress information for the waiting queue, emitted while a convert task
/// is queued behind other users.
class QueueStatus {
  const QueueStatus({
    this.position,
    this.total,
    this.etaMs,
    this.waitingMessage,
  });

  final int? position;
  final int? total;
  final int? etaMs;
  final String? waitingMessage;
}

/// The aggregated outcome of a convert task.
class ConvertResult {
  ConvertResult({
    List<String>? links,
    List<String>? exeUrls,
    List<String>? tokens,
  })  : links = links ?? <String>[],
        exeUrls = exeUrls ?? <String>[],
        tokens = tokens ?? <String>[];

  /// Direct download URLs usable by a mobile client.
  final List<String> links;

  /// Upstream paths that can produce an `.exe` downloader (PC only).
  final List<String> exeUrls;

  /// 32-char hex identifiers occasionally emitted alongside links.
  final List<String> tokens;

  bool get isEmpty => links.isEmpty && exeUrls.isEmpty && tokens.isEmpty;
}

/// A single decoded Server-Sent-Event frame from the convert stream.
class ConvertEvent {
  const ConvertEvent({required this.step, required this.data});

  /// Machine-readable step name, e.g. `queue`, `convert`, `done`, `retry`.
  final String step;
  final Map<String, dynamic> data;

  bool get isError {
    final err = data['error'];
    return err is num && err != 0;
  }

  String? get message {
    final msg = data['msg'];
    return msg is String && msg.isNotEmpty ? msg : null;
  }
}

/// Thrown for any upstream/network failure that should be surfaced to the user
/// as a human-readable message.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
