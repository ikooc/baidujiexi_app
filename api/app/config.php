<?php
/**
 * Backend-issued app configuration.
 *
 * GET  /api/app/config.php            -> return current config (public, read-only)
 * POST /api/app/config.php            -> update config (requires admin token)
 *
 * The Flutter app boots from this endpoint and never hard-codes the convert
 * API host, so the host can be migrated without shipping a new build.
 *
 * The config lives in config.json next to this file. Edit it directly on the
 * server, or POST JSON to this endpoint with the admin token below.
 */

declare(strict_types=1);

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/** Shared secret required to write config. CHANGE THIS before deploying. */
const ADMIN_TOKEN = 'CHANGE_ME_admin_token';

/** Fallback used when config.json is missing or corrupt. */
const DEFAULT_CONFIG = [
    'apiBase'       => 'https://file.mdx.wang',
    'siteOrigin'    => 'https://file.mdx.wang',
    'referer'       => 'https://file.mdx.wang/',
    'fallbackBases' => [],
    'defaultMode'   => 'web',
    'configVersion' => 1,
    'announcement'  => '',
    // 启动弹窗公告（私有模块消费，客户端按 popup 字段解析）。
    // 结构见 defaultPopup()，enabled=false 时不弹窗。
    'popup'         => [
        'enabled'     => false,
        'title'       => '',
        'content'     => '',
        'actionType'  => 'none', // none | link | qq
        'actionLabel' => '',
        'actionValue' => '',
        'dismissible' => true,
    ],
];

/** Absolute path of the mutable config file. */
$configFile = __DIR__ . DIRECTORY_SEPARATOR . 'config.json';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Sends a JSON response and terminates.
 *
 * @param array<string,mixed> $payload
 */
function respond(array $payload, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    // Read-only public endpoint: allow any client (the app is native, but this
    // also makes manual browser testing painless).
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Admin-Token');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Cache-Control: no-store, max-age=0');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * Normalizes a URL-ish string: trims whitespace and trailing slashes.
 */
function normalizeUrl(string $value): string
{
    return rtrim(trim($value), '/');
}

/**
 * 弹窗公告的默认/字段白名单结构。
 *
 * @return array<string,mixed>
 */
function defaultPopup(): array
{
    return [
        'enabled'     => false,
        'title'       => '',
        'content'     => '',
        'actionType'  => 'none',
        'actionLabel' => '',
        'actionValue' => '',
        'dismissible' => true,
    ];
}

/**
 * 规范化弹窗公告配置，仅保留白名单字段。
 *
 * @param mixed $input
 * @return array<string,mixed>
 */
function sanitizePopup($input): array
{
    $popup = defaultPopup();
    if (!is_array($input)) {
        return $popup;
    }

    $popup['enabled'] = filter_var($input['enabled'] ?? false, FILTER_VALIDATE_BOOLEAN);

    $popup['title']   = trim((string) ($input['title'] ?? ''));
    $popup['content'] = trim((string) ($input['content'] ?? ''));

    $type = (string) ($input['actionType'] ?? 'none');
    if (!in_array($type, ['none', 'link', 'qq'], true)) {
        $type = 'none';
    }
    $popup['actionType'] = $type;

    $popup['actionLabel'] = trim((string) ($input['actionLabel'] ?? ''));
    $popup['actionValue'] = trim((string) ($input['actionValue'] ?? ''));
    $popup['dismissible'] = filter_var($input['dismissible'] ?? true, FILTER_VALIDATE_BOOLEAN);

    // 有跳转目标才允许启用动作，避免空按钮。
    if ($popup['actionValue'] === '') {
        $popup['actionType'] = 'none';
    }

    return $popup;
}

/**
 * Loads config from disk, falling back to DEFAULT_CONFIG.
 *
 * @return array<string,mixed>
 */
function loadConfig(string $file): array
{
    if (!is_readable($file)) {
        return DEFAULT_CONFIG;
    }
    $raw = file_get_contents($file);
    if ($raw === false || trim($raw) === '') {
        return DEFAULT_CONFIG;
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return DEFAULT_CONFIG;
    }
    $merged = array_merge(DEFAULT_CONFIG, $decoded);
    $merged['popup'] = sanitizePopup($merged['popup'] ?? []);
    return $merged;
}

/**
 * Validates and normalizes an incoming config payload.
 *
 * @param array<string,mixed> $input
 * @return array<string,mixed>
 */
function sanitizeConfig(array $input): array
{
    $apiBase = normalizeUrl((string) ($input['apiBase'] ?? ''));
    if ($apiBase === '') {
        respond(['code' => 1, 'msg' => 'apiBase 不能为空'], 400);
    }
    if (!preg_match('#^https?://#i', $apiBase)) {
        respond(['code' => 1, 'msg' => 'apiBase 必须是 http/https 地址'], 400);
    }

    $siteOrigin = normalizeUrl((string) ($input['siteOrigin'] ?? ''));
    if ($siteOrigin === '') {
        $siteOrigin = $apiBase;
    }

    $referer = trim((string) ($input['referer'] ?? ''));
    if ($referer === '') {
        $referer = $apiBase . '/';
    }

    $fallbacks = [];
    if (isset($input['fallbackBases']) && is_array($input['fallbackBases'])) {
        foreach ($input['fallbackBases'] as $item) {
            $normalized = normalizeUrl((string) $item);
            if ($normalized !== '' && $normalized !== $apiBase && !in_array($normalized, $fallbacks, true)) {
                $fallbacks[] = $normalized;
            }
        }
    }

    $mode = (string) ($input['defaultMode'] ?? 'web');
    if (!in_array($mode, ['web', 'exe'], true)) {
        $mode = 'web';
    }

    return [
        'apiBase'       => $apiBase,
        'siteOrigin'    => $siteOrigin,
        'referer'       => $referer,
        'fallbackBases' => $fallbacks,
        'defaultMode'   => $mode,
        'configVersion' => (int) ($input['configVersion'] ?? time()),
        'announcement'  => trim((string) ($input['announcement'] ?? '')),
        'popup'         => sanitizePopup($input['popup'] ?? []),
        'updatedAt'     => date('c'),
    ];
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'OPTIONS') {
    respond(['code' => 0]);
}

if ($method === 'GET') {
    respond(['code' => 0, 'data' => loadConfig($configFile)]);
}

if ($method === 'POST') {
    $token = $_SERVER['HTTP_X_ADMIN_TOKEN'] ?? '';
    if (!hash_equals(ADMIN_TOKEN, (string) $token)) {
        respond(['code' => 1, 'msg' => '无权修改配置'], 403);
    }

    $body = file_get_contents('php://input');
    $input = json_decode((string) $body, true);
    if (!is_array($input)) {
        respond(['code' => 1, 'msg' => '请求体必须是 JSON'], 400);
    }

    $config = sanitizeConfig($input);
    $written = file_put_contents(
        $configFile,
        json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
        LOCK_EX
    );
    if ($written === false) {
        respond(['code' => 1, 'msg' => '配置写入失败，请检查目录权限'], 500);
    }

    respond(['code' => 0, 'msg' => '配置已更新', 'data' => $config]);
}

respond(['code' => 1, 'msg' => '不支持的请求方法'], 405);
