# netdiskx_app

网盘直链解析助手的 Flutter 客户端（Android / Windows）。通过远端配置获取解析接口地址，解析网盘分享链接得到直链，并调用内置 [Gopeed](https://gopeed.com/) 引擎进行多线程下载。

本仓库为**开源版本**，仅包含通用客户端功能；启动弹窗公告等业务定制模块为闭源私有实现，不在此仓库内（见下文「开源 / 闭源分离」）。

## 功能概览

- 远端配置：启动时从 `apiBase` 拉取配置（站点地址、备用接口、默认模式、公告等），支持多备用地址回退
- 直链解析：输入网盘分享链接，调用远端接口解析出可直接下载的直链
- 多线程下载：内置 Gopeed 引擎（Android 走 `libgopeed.aar`，Windows 走 `gopeed-rest.exe`），支持暂停 / 继续 / 删除
- 下载目录：可选自定义目录，默认 `/storage/emulated/0/Download/`，适配 Android 7–16
- 云端公告：首页展示远端下发的公告内容
- 界面：Material 3 主题，跟随系统亮色 / 暗色

## 目录结构

```
lib/
  main.dart              开源入口（零私有依赖）
  core/
    api_client.dart       远端接口调用
    remote_config.dart    AppConfig 配置解析（含 extras 透传）
    download_manager.dart 下载任务管理
    gopeed_engine.dart    Gopeed 引擎桥接
    storage_service.dart  存储 / 下载目录
    startup_hooks.dart    启动钩子扩展点（私有模块挂载点）
    models.dart           数据模型
    crypto.dart           签名 / 加密封装
  theme/app_theme.dart    主题
  ui/
    home_page.dart        首页
    downloads_page.dart   下载列表
```

## 开源 / 闭源分离

开源代码与私有定制通过两个扩展点解耦，私有模块被 `.gitignore` 排除，不在本仓库中：

- **启动钩子扩展点**：`lib/core/startup_hooks.dart` 提供 `StartupHooks.register(...)`。开源构建不注册任何钩子；私有构建在该时机注入弹窗公告等逻辑。
- **配置透传**：`AppConfig.extras` / `extra<T>()` 会原样保留远端返回的未知字段（如 `popup`），供私有模块自行解析，开源侧无需感知。

私有侧约定（不在本仓库）：

- 实现放在 `lib/private/`，私有入口为 `lib/main_private.dart`
- 私有入口 `import 'main.dart'` 复用 `runNetdiskxApp()`，先注册私有模块再启动

对应的 `.gitignore` 规则：

```
/lib/private/
/lib/main_private.dart
/.trae/
```

## 构建

```bash
flutter pub get

# 开源版（Android）
flutter build apk --release

# 私有版（含闭源模块，仅在私有工作区执行）
flutter build apk --release --target-platform android-arm64 --target lib/main_private.dart

# Windows
flutter build windows --release
```

校验：

```bash
flutter analyze
flutter test
```

## 依赖

主要依赖见 `pubspec.yaml`：`http`、`shared_preferences`、`url_launcher`、`path`、`path_provider`。

`android/app/libs/libgopeed.aar`、`android/app/src/main/jniLibs/arm64-v8a/libc++_shared.so`、`windows/runner/gopeed-rest.exe` 为 Gopeed 引擎运行库，随仓库提供以支持直接构建。
