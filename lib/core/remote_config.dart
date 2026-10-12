/// Remote configuration layer.
///
/// The app never hard-codes the upstream convert API host. Instead it boots
/// from a small list of well-known *bootstrap* endpoints, downloads a JSON
/// config that declares the real API base + the `Origin`/`Referer` the
/// upstream expects, and caches it locally so the app still works when the
/// bootstrap endpoint is temporarily unreachable.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Bootstrap endpoints queried (in order) until one returns a valid config.
///
/// These are intentionally the only baked-in values. Everything else — the
/// real API host, the fallback hosts, the referer — is delivered by the
/// backend so the operator can migrate hosts without shipping a new build.
///
/// Override at build time with:
///   flutter build apk --dart-define=BOOTSTRAP_URL=https://your.domain/api/app/config.php
const String _bootstrapOverride =
    String.fromEnvironment('BOOTSTRAP_URL', defaultValue: '');

const List<String> kDefaultBootstrapUrls = <String>[
  'https://hhh.com/api/app/config.php',
  'http://hhh.com/api/app/config.php',
];

/// The bootstrap URLs actually used, honouring [BOOTSTRAP_URL] if provided.
List<String> get kBootstrapUrls => _bootstrapOverride.isNotEmpty
    ? <String>[_bootstrapOverride]
    : kDefaultBootstrapUrls;

/// Fully-resolved runtime configuration used by the API client.
class AppConfig {
  const AppConfig({
    required this.apiBase,
    required this.siteOrigin,
    required this.referer,
    this.fallbackBases = const <String>[],
    this.defaultMode = 'web',
    this.configVersion = 0,
    this.announcement = '',
    this.extras = const <String, dynamic>{},
  });

  /// Base URL of the convert API, e.g. `https://file.mdx.wang`.
  /// No trailing slash.
  final String apiBase;

  /// Value injected as the `Origin` header. Upstream rejects requests whose
  /// origin does not match the site that issued the session.
  final String siteOrigin;

  /// Value injected as the `Referer` header.
  final String referer;

  /// Additional API hosts tried if [apiBase] fails at request time.
  final List<String> fallbackBases;

  /// Default convert mode: `web` (direct links) or `exe` (PC downloader).
  final String defaultMode;

  /// Monotonic version supplied by the backend, used to detect stale cache.
  final int configVersion;

  /// Operator-pushed announcement shown on the home screen. Empty = hidden.
  final String announcement;

  /// Raw config keys not consumed by the open-source layer.
  ///
  /// The backend may ship extra fields (e.g. a popup announcement) that only
  /// optional/private modules understand. They are preserved verbatim here so
  /// those modules can read their own values without the open-source code
  /// knowing anything about them.
  final Map<String, dynamic> extras;

  /// Every host that may serve the API, primary first.
  List<String> get allBases => <String>[apiBase, ...fallbackBases];

  /// Reads an unknown, module-private config value by key.
  T? extra<T>(String key) {
    final value = extras[key];
    return value is T ? value : null;
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final base = _normalizeBase((json['apiBase'] ?? '').toString());
    if (base.isEmpty) {
      throw ApiException('远程配置缺少 apiBase 字段');
    }
    final rawFallbacks = json['fallbackBases'];
    final fallbacks = <String>[];
    if (rawFallbacks is List) {
      for (final item in rawFallbacks) {
        final normalized = _normalizeBase(item.toString());
        if (normalized.isNotEmpty && normalized != base) {
          fallbacks.add(normalized);
        }
      }
    }
    final origin = (json['siteOrigin'] ?? '').toString().trim();
    final extras = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        extras[entry.key] = entry.value;
      }
    }
    return AppConfig(
      apiBase: base,
      siteOrigin: origin.isNotEmpty ? _normalizeBase(origin) : base,
      referer: (json['referer'] ?? '').toString().trim().isNotEmpty
          ? json['referer'].toString().trim()
          : '$base/',
      fallbackBases: fallbacks,
      defaultMode: (json['defaultMode'] ?? 'web').toString(),
      configVersion: (json['configVersion'] as num?)?.toInt() ?? 0,
      announcement: (json['announcement'] ?? '').toString().trim(),
      extras: extras,
    );
  }

  /// Keys understood by the open-source layer; everything else lands in
  /// [extras] untouched.
  static const Set<String> _knownKeys = <String>{
    'apiBase',
    'siteOrigin',
    'referer',
    'fallbackBases',
    'defaultMode',
    'configVersion',
    'announcement',
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiBase': apiBase,
        'siteOrigin': siteOrigin,
        'referer': referer,
        'fallbackBases': fallbackBases,
        'defaultMode': defaultMode,
        'configVersion': configVersion,
        'announcement': announcement,
        ...extras,
      };

  static String _normalizeBase(String value) {
    var v = value.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }
}

/// Loads [AppConfig] from the backend, with local cache + built-in fallback.
class RemoteConfigService {
  RemoteConfigService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _cacheKey = 'remote_config_v1';
  static const String _cacheAtKey = 'remote_config_at_v1';

  /// Built-in default used only if both the network and the cache fail.
  /// Points at the public upstream so a fresh install is never dead.
  static const AppConfig _hardFallback = AppConfig(
    apiBase: 'https://file.mdx.wang',
    siteOrigin: 'https://file.mdx.wang',
    referer: 'https://file.mdx.wang/',
  );

  /// Resolves the config: network first, then cache, then hard fallback.
  ///
  /// [bootstrapUrls] overrides [kBootstrapUrls] (useful for testing).
  Future<AppConfig> load({List<String>? bootstrapUrls}) async {
    final urls = bootstrapUrls ?? kBootstrapUrls;

    for (final url in urls) {
      try {
        final config = await _fetch(url);
        await _cache(config);
        return config;
      } catch (_) {
        // Try the next bootstrap endpoint.
      }
    }

    final cached = await _readCache();
    if (cached != null) return cached;

    return _hardFallback;
  }

  Future<AppConfig> _fetch(String url) async {
    final uri = Uri.parse(url);
    final response = await _client
        .get(uri, headers: <String, String>{'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw ApiException('配置接口返回 ${response.statusCode}', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('配置接口返回格式不正确');
    }

    // Allow the backend to wrap the payload: {"code":0,"data":{...}}
    final data = decoded['data'];
    final payload = data is Map<String, dynamic> ? data : decoded;
    return AppConfig.fromJson(payload);
  }

  Future<void> _cache(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(config.toJson()));
    await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<AppConfig?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AppConfig.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Timestamp (epoch ms) of the last successful config download, if any.
  Future<int?> lastCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cacheAtKey);
  }
}
