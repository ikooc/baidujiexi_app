import 'package:flutter/material.dart';

import 'core/remote_config.dart';
import 'core/startup_hooks.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

/// 应用入口：构建并运行 App 外壳。
void main() {
  runBaidujiexiApp();
}

/// 构建并运行 App 外壳。
///
/// 若需在启动前注册扩展逻辑，可先调用 `StartupHooks.register`，再复用本函数。
void runBaidujiexiApp() {
  runApp(const BaidujiexiApp());
}

class BaidujiexiApp extends StatefulWidget {
  const BaidujiexiApp({super.key});

  @override
  State<BaidujiexiApp> createState() => _BaidujiexiAppState();
}

class _BaidujiexiAppState extends State<BaidujiexiApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '百度解析助手',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      // AppTheme.light / AppTheme.dark 在构造时会调用 AppColors.setBrightness 以便
      // 让各自的 ThemeData 子主题取到正确颜色，因此后构造的 darkTheme 会把全局调色板
      // 遗留在深色。这里在主题解析完成后按实际生效的亮度重新同步，避免出现「浅色页面
      // 配深色卡片」的配色错乱。
      builder: (context, child) {
        AppColors.setBrightness(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
      home: _Bootstrap(onToggleTheme: _toggleTheme),
    );
  }
}

/// Boots the app by fetching the backend-issued config before showing the
/// main screen. The API host is never hard-coded in the UI.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  final RemoteConfigService _service = RemoteConfigService();

  late Future<AppConfig> _future;

  /// Guards [StartupHooks.run] so registered hooks fire only once per launch.
  bool _hooksRan = false;

  @override
  void initState() {
    super.initState();
    _future = _service.load();
  }

  Future<AppConfig> _reload() async {
    final config = await _service.load();
    setState(() => _future = Future<AppConfig>.value(config));
    return config;
  }

  /// Fires the optional startup hooks after the first main-screen frame so a
  /// hook can present dialogs with a mounted context.
  void _runStartupHooks(AppConfig config) {
    if (_hooksRan) return;
    _hooksRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      StartupHooks.run(context, config);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppConfig>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _BootScaffold(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 20),
                Text('正在获取接口配置…'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return _BootScaffold(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined, size: 56),
                  const SizedBox(height: 18),
                  Text(
                    '配置加载失败',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _future = _service.load();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        final config = snapshot.data!;
        _runStartupHooks(config);
        return HomePage(
          config: config,
          onReloadConfig: _reload,
          onToggleTheme: widget.onToggleTheme,
        );
      },
    );
  }
}

class _BootScaffold extends StatelessWidget {
  const _BootScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: child));
  }
}
