import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/download_manager.dart';
import '../core/models.dart';
import '../core/remote_config.dart';
import '../theme/app_theme.dart';
import 'downloads_page.dart';

/// Main screen: paste a share link, watch the SSE progress, then send the
/// resolved direct links to the built-in Gopeed download engine.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.config,
    required this.onReloadConfig,
    required this.onToggleTheme,
  });

  final AppConfig config;

  /// Re-runs the remote-config bootstrap (used by the refresh button).
  final Future<AppConfig> Function() onReloadConfig;

  /// Switches between the light and dark palettes.
  final VoidCallback onToggleTheme;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _linkController = TextEditingController();
  final FocusNode _linkFocus = FocusNode();

  final DownloadManager _downloads = DownloadManager.instance;

  late ConvertApiClient _client;
  late AppConfig _config;

  bool _running = false;
  String? _statusText;
  String? _errorText;
  ConvertResult? _result;
  final List<String> _logs = <String>[];
  bool _logsExpanded = false;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _client = ConvertApiClient(_config);
  }

  @override
  void dispose() {
    _linkController.dispose();
    _linkFocus.dispose();
    _client.dispose();
    super.dispose();
  }

  void _appendLog(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _logs.add(text);
      if (_logs.length > 40) _logs.removeAt(0);
    });
  }

  Future<void> _reloadConfig() async {
    setState(() {
      _statusText = '正在刷新接口配置…';
      _errorText = null;
    });
    try {
      final fresh = await widget.onReloadConfig();
      _client.dispose();
      setState(() {
        _config = fresh;
        _client = ConvertApiClient(_config);
        _statusText = '接口配置已更新';
      });
      _appendLog('接口地址: ${fresh.apiBase}');
    } catch (error) {
      setState(() => _errorText = '刷新配置失败：$error');
    }
  }

  Future<void> _startConvert() async {
    final link = _linkController.text.trim();
    if (link.isEmpty) {
      setState(() => _errorText = '请先粘贴网盘分享链接');
      _linkFocus.requestFocus();
      return;
    }

    _linkFocus.unfocus();
    setState(() {
      _running = true;
      _errorText = null;
      _statusText = '正在建立会话…';
      _result = null;
      _logs.clear();
    });

    try {
      final result = await _client.convertToResult(
        link,
        onEvent: (event) {
          final msg = event.message;
          if (msg != null) _appendLog(msg);
          final step = event.step;
          if (step == 'done') {
            setState(() => _statusText = '转换完成');
          } else if (step.isNotEmpty) {
            setState(() => _statusText = msg ?? _stepLabel(step));
          }
        },
      );

      setState(() {
        _result = result;
        _statusText = result.isEmpty ? '未解析到可用下载地址' : '转换完成';
      });
    } on ApiException catch (error) {
      setState(() => _errorText = error.message);
    } catch (error) {
      setState(() => _errorText = '请求失败：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _stepLabel(String step) {
    switch (step) {
      case 'queue':
        return '排队中…';
      case 'convert':
        return '正在转换…';
      case 'retry':
        return '重试中…';
      default:
        return step;
    }
  }

  /// 把直链交给内嵌 Gopeed 引擎下载。
  Future<void> _downloadWithEngine(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final item = await _downloads.download(url: url);
      messenger.showSnackBar(
        SnackBar(content: Text('已添加到下载任务：${item.name}')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('创建下载任务失败：$error')),
      );
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await _copy(url, message: '无法直接打开，已复制链接到剪贴板');
    }
  }

  Future<void> _copy(String value, {String message = '已复制到剪贴板'}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() => _linkController.text = text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('百度解析助手'),
        actions: <Widget>[
          IconButton(
            tooltip: isDark ? '切换浅色' : '切换深色',
            onPressed: widget.onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
          IconButton(
            tooltip: '下载任务',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadsPage(),
              ),
            ),
            icon: const Icon(Icons.download_for_offline_rounded),
          ),
          IconButton(
            tooltip: '刷新接口配置',
            onPressed: _running ? null : _reloadConfig,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _buildHero(theme),
            if (_config.announcement.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _buildAnnouncement(theme),
            ],
            const SizedBox(height: 20),
            Text('分享链接', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _linkController,
              focusNode: _linkFocus,
              enabled: !_running,
              maxLines: 3,
              minLines: 3,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: '粘贴百度网盘分享链接（含提取码）',
                suffixIcon: IconButton(
                  tooltip: '粘贴',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _running ? null : _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _running ? null : _startConvert,
                icon: _running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_running ? '处理中…' : '解析直链'),
              ),
            ),
            if (_statusText != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildStatusRow(theme),
            ],
            if (_errorText != null) ...<Widget>[
              const SizedBox(height: 14),
              _buildError(theme),
            ],
            if (_result != null && !_result!.isEmpty) ...<Widget>[
              const SizedBox(height: 26),
              _buildSectionTitle(theme, '下载结果', Icons.link_rounded),
              const SizedBox(height: 12),
              ..._result!.links.asMap().entries.map(
                    (e) {
                      // 解析文件夹时，卡片标题直接使用待下载文件的真实名称。
                      final fileName = DownloadManager.fileNameFromUrl(e.value);
                      return _buildResultCard(
                        theme,
                        index: e.key + 1,
                        title: fileName ?? '直链地址',
                        value: e.value,
                        icon: Icons.link_rounded,
                        primaryIcon: Icons.rocket_launch_rounded,
                        primaryLabel: '引擎下载',
                        onPrimary: () => _downloadWithEngine(e.value),
                        secondaryLabel: '复制',
                        onSecondary: () => _copy(e.value),
                      );
                    },
                  ),
              ..._result!.exeUrls.map(
                    (url) => _buildResultCard(
                      theme,
                      title: 'PC 下载器 (EXE)',
                      value: url,
                      icon: Icons.desktop_windows_rounded,
                      primaryIcon: Icons.open_in_new_rounded,
                      primaryLabel: '打开',
                      onPrimary: () => _openLink(url),
                      secondaryLabel: '复制',
                      onSecondary: () => _copy(url),
                    ),
                  ),
              ..._result!.tokens.map(
                    (token) => _buildResultCard(
                      theme,
                      title: 'Token',
                      value: token,
                      icon: Icons.key_rounded,
                      primaryIcon: Icons.copy_all_rounded,
                      primaryLabel: '复制',
                      onPrimary: () => _copy(token),
                    ),
                  ),
            ],
            if (_logs.isNotEmpty) ...<Widget>[
              const SizedBox(height: 26),
              _buildLogs(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0A8CFF), Color(0xFF3AA6FF)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0A8CFF).withValues(alpha: 0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: CustomPaint(
                size: Size(30, 30),
                painter: _BaiduPawPainter(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '网盘直链解析',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '解析分享链接为直链，内置引擎多线程加速下载',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 云端公告：由后端 `announcement` 字段下发，为空时整块隐藏。
  Widget _buildAnnouncement(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.campaign_rounded,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('公告', style: theme.textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(
                  _config.announcement,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          if (_running)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }

  Widget _buildResultCard(
    ThemeData theme, {
    int? index,
    required String title,
    required String value,
    required IconData icon,
    required IconData primaryIcon,
    required String primaryLabel,
    required VoidCallback onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  index != null ? '$title  #$index' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(primaryIcon, size: 18),
                  label: Text(primaryLabel),
                ),
              ),
              if (secondaryLabel != null && onSecondary != null) ...<Widget>[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogs(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: <Widget>[
                Icon(Icons.receipt_long_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('处理日志', style: theme.textTheme.titleMedium),
                ),
                Text(
                  '${_logs.length}',
                  style: theme.textTheme.bodySmall,
                ),
                Icon(
                  _logsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          if (_logsExpanded) ...<Widget>[
            const SizedBox(height: 12),
            ..._logs.map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 百度品牌「熊掌」标识：四个脚趾 + 下方肉垫，品牌蓝 #2932E1。
class _BaiduPawPainter extends CustomPainter {
  const _BaiduPawPainter();

  static const Color _brandBlue = Color(0xFF2932E1);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _brandBlue
      ..isAntiAlias = true;

    // 以 30x30 为设计基准，按实际尺寸等比缩放。
    final s = size.width / 30.0;
    RRect oval(double l, double t, double w, double h) => RRect.fromRectAndRadius(
          Rect.fromLTWH(l * s, t * s, w * s, h * s),
          Radius.elliptical(w * s / 2, h * s / 2),
        );

    // 下方肉垫（大）
    canvas.drawRRect(oval(6, 14, 18, 13), paint);
    // 四个脚趾（上方呈弧形排布）
    canvas.drawRRect(oval(3.5, 8, 6.5, 7.5), paint);
    canvas.drawRRect(oval(9.5, 3.5, 6.5, 8), paint);
    canvas.drawRRect(oval(15, 3.5, 6.5, 8), paint);
    canvas.drawRRect(oval(21, 8, 6.5, 7.5), paint);
  }

  @override
  bool shouldRepaint(covariant _BaiduPawPainter oldDelegate) => false;
}

