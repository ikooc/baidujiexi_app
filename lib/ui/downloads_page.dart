import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/download_manager.dart';
import '../theme/app_theme.dart';

/// 下载任务面板：展示 Gopeed 引擎中的任务进度，支持暂停 / 继续 / 删除。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManager _manager = DownloadManager.instance;
  String _dirLabel = '解析中…';

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onChanged);
    _manager.restore();
    _refreshDir();
  }

  @override
  void dispose() {
    _manager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshDir() async {
    final dir = await _manager.effectiveDir();
    if (mounted) setState(() => _dirLabel = dir);
  }

  /// 打开「下载目录」设置面板。
  Future<void> _openDirSheet() async {
    final hasPerm = await _manager.hasStoragePermission();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _DirSheet(
        manager: _manager,
        initialDir: _dirLabel,
        hasPermission: hasPerm,
        onChanged: _refreshDir,
      ),
    );
    await _refreshDir();
  }

  Future<void> _confirmRemove(DownloadItem item) async {
    final deleteFile = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${item.name}」'),
        content: const Text('是否同时删除已下载的文件？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留文件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('一并删除'),
          ),
        ],
      ),
    );
    if (deleteFile == null) return;
    await _manager.remove(item.gopeedId, deleteFile: deleteFile);
  }

  @override
  Widget build(BuildContext context) {
    final items = _manager.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载任务'),
        actions: <Widget>[
          IconButton(
            tooltip: '下载目录',
            onPressed: _openDirSheet,
            icon: const Icon(Icons.folder_outlined),
          ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${items.where((e) => e.status == DownloadStatus.running).length} 个进行中',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildDirBar(),
            Expanded(
              child: items.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildCard(items[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部下载目录提示条，点击可更改目录。
  Widget _buildDirBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InkWell(
        onTap: _openDirSheet,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_special_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('下载目录',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      _manager.isCustomDir ? '$_dirLabel（自定义）' : _dirLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.download_done_rounded,
              size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('暂无下载任务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '在解析结果中点击「引擎下载」即可创建任务',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(DownloadItem item) {
    final theme = Theme.of(context);
    final color = _statusColor(item.status);

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 10),
              _statusChip(item.status, color),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceSoft,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  <String>[
                    item.sizeLabel,
                    if (item.progress != null)
                      '${(item.progress! * 100).toStringAsFixed(1)}%',
                    if (item.speedLabel.isNotEmpty) item.speedLabel,
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              _iconAction(
                icon: item.status == DownloadStatus.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                tooltip: item.status == DownloadStatus.paused ? '继续' : '暂停',
                enabled: item.status == DownloadStatus.running ||
                    item.status == DownloadStatus.paused,
                onTap: () => item.status == DownloadStatus.paused
                    ? _manager.resume(item.gopeedId)
                    : _manager.pause(item.gopeedId),
              ),
              _iconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: '删除',
                enabled: true,
                onTap: () => _confirmRemove(item),
              ),
            ],
          ),
          if (item.error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              item.error!,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.done:
        return AppColors.success;
      case DownloadStatus.error:
        return AppColors.danger;
      case DownloadStatus.paused:
        return AppColors.warning;
      case DownloadStatus.running:
        return AppColors.primary;
      default:
        return AppColors.textMuted;
    }
  }

  Widget _statusChip(DownloadStatus status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon),
        visualDensity: VisualDensity.compact,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// 下载目录设置面板：展示 / 修改当前目录，处理存储权限。
class _DirSheet extends StatefulWidget {
  const _DirSheet({
    required this.manager,
    required this.initialDir,
    required this.hasPermission,
    required this.onChanged,
  });

  final DownloadManager manager;
  final String initialDir;
  final bool hasPermission;
  final Future<void> Function() onChanged;

  @override
  State<_DirSheet> createState() => _DirSheetState();
}

class _DirSheetState extends State<_DirSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialDir);
  late bool _hasPermission = widget.hasPermission;
  String? _error;
  bool _busy = false;

  /// 当前是否为 Android 平台（决定存储权限相关的文案与入口）。
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.manager.setDownloadDir(path);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '保存失败，请确认目录可写（避免系统保护目录），然后重试';
      });
      return;
    }
    await widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.manager.resetDownloadDir();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '恢复默认目录失败，请重试';
      });
      return;
    }
    await widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _requestPermission() async {
    await widget.manager.requestStoragePermission();
    if (!mounted) return;
    // Android 11+ 需用户从系统设置页返回，此处重新查询状态。
    final granted = await widget.manager.hasStoragePermission();
    if (mounted) setState(() => _hasPermission = granted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('下载目录', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            _isAndroid
                ? '默认目录为 /storage/emulated/0/Download/，可自定义为任意可写路径。'
                : '默认使用系统下载目录，可自定义为任意可写路径（如 D:\\）。',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          if (_isAndroid && !_hasPermission)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '写入公共目录需要存储权限（Android 11+ 为「所有文件访问」）',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestPermission,
                    child: const Text('去授权'),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _controller,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: '目录路径',
              hintText: _isAndroid ? '/storage/emulated/0/Download/' : r'D:\Downloads',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reset,
                  child: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _apply(_controller.text),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
