/// Data models shared between the API client and the UI layer.
library;

/// A short-lived session returned by `/api/session`.
///
/// The upstream issues two kinds of sessions:
///  * legacy — the response already carries a `secret`;
///  * attested — the response carries only `token` plus `attest: 1`, and the
///    signing `secret` must be obtained separately from
///    `POST /api/session/attest` using a behavioural fingerprint.
///
/// [secret] is never sent upstream directly; it is only used locally to
/// compute request signatures.
class ApiSession {
  const ApiSession({
    required this.token,
    required this.secret,
    required this.ttl,
    this.attestRequired = false,
  });

  final String token;

  /// May be empty when [attestRequired] is set: fetch it via attestation.
  final String secret;

  /// Lifetime in milliseconds as reported by the server (default 30 min).
  final int ttl;

  /// Whether `secret` must be fetched from `/api/session/attest`.
  final bool attestRequired;

  DateTime get expiresAt => DateTime.now().add(Duration(milliseconds: ttl));

  factory ApiSession.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] ?? '').toString();
    final secret = (json['secret'] ?? '').toString();
    return ApiSession(
      token: token,
      secret: secret,
      ttl: (json['ttl'] as num?)?.toInt() ?? 1800000,
      attestRequired: secret.isEmpty && (json['attest'] as num?)?.toInt() == 1,
    );
  }

  /// A session is usable as long as it carries a token; a legacy response may
  /// already include the secret, otherwise it is attested later.
  bool get isValid => token.isNotEmpty;

  /// Whether local request signing is possible with this object alone.
  bool get canSign => token.isNotEmpty && secret.isNotEmpty;
}

/// The curve-follow slider challenge returned by `/api/captcha`.
///
/// Unlike a jigsaw slider there is no gap to locate: the knob must be dragged
/// along the dashed `curve` all the way to the right end, so the correct
/// answer is always the maximum travel and only the trail shape matters.
class CaptchaChallenge {
  const CaptchaChallenge({
    required this.captchaId,
    required this.curve,
    required this.curveStartY,
    this.width = 300,
    this.height = 96,
    this.trackH = 150,
    this.bg = '',
  });

  final String captchaId;

  /// SVG path (`M x y C …`) describing the dashed guide curve.
  final String curve;

  /// Y coordinate where the knob rests before any drag.
  final double curveStartY;

  /// Canvas width in logical pixels.
  final double width;

  /// Canvas height in logical pixels.
  final double height;

  /// Height of the vertical track the knob may move within.
  final double trackH;

  /// Decorative background (an inline SVG data URL); unused when solving
  /// programmatically.
  final String bg;

  factory CaptchaChallenge.fromJson(Map<String, dynamic> json) {
    return CaptchaChallenge(
      captchaId: (json['captchaId'] ?? '').toString(),
      curve: (json['curve'] ?? '').toString(),
      curveStartY: (json['curveStartY'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 300,
      height: (json['height'] as num?)?.toDouble() ?? 96,
      trackH: (json['trackH'] as num?)?.toDouble() ?? 150,
      bg: (json['bg'] ?? '').toString(),
    );
  }

  bool get isValid => captchaId.isNotEmpty && curve.isNotEmpty;
}

/// An algorithmically-produced captcha solution, submitted with a convert
/// request as `captchaId` / `captchaAnswer` / `captchaTrail`.
class CaptchaAnswer {
  const CaptchaAnswer({
    required this.captchaId,
    required this.answer,
    required this.trail,
  });

  final String captchaId;

  /// Final knob-centre X, always the maximum travel for this challenge.
  final double answer;

  /// Recorded drag samples: `{'t': epochMs, 'x': int, 'y': int}`.
  final List<Map<String, int>> trail;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'captchaId': captchaId,
        'captchaAnswer': answer,
        'captchaTrail': trail,
      };
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
