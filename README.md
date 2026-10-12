# baidujiexi_app

网盘直链解析助手的 Flutter 客户端（Android / Windows）。

App 不硬编码任何上游接口域名，启动时从远端配置接口拉取真实 API 地址，把用户粘贴的网盘分享链接解析为可直接下载的直链，再交给内置的 [Gopeed](https://gopeed.com/) 下载引擎进行多线程下载。

- Android：Gopeed 以 `libgopeed.aar` 形式内嵌，通过 MethodChannel 与 Dart 通信
- Windows：以子进程 `gopeed-rest.exe` 运行，通过本地 REST API 通信

---

## 功能概览

| 模块 | 说明 |
| --- | --- |
| 远端配置 | 启动时从 bootstrap 地址拉取 JSON 配置（API 地址、备用地址、`Origin`/`Referer`、默认模式、公告等），本地缓存以支持离线启动与多地址回退 |
| 直链解析 | 输入网盘分享链接（支持整段分享文本），调用远端接口以 SSE 流式返回解析进度与结果 |
| 多线程下载 | 内置 Gopeed 引擎，支持暂停 / 继续 / 删除 / 强制删除，单任务进度实时刷新 |
| 下载目录 | 默认 `/storage/emulated/0/Download/`，支持用户自定义目录并持久化，适配 Android 7–16 的存储权限差异 |
| 云端公告 | 首页展示后端下发的公告内容；内容为空时整块隐藏 |
| 主题 | Material 3，跟随系统亮色 / 暗色，并可手动切换 |

---

## 目录结构

```
baidujiexi_app/
├── lib/
│   ├── main.dart                  应用入口与根 Widget（启动引导、主题切换）
│   ├── core/
│   │   ├── remote_config.dart     远端配置拉取 / 解析 / 缓存（AppConfig）
│   │   ├── api_client.dart        转换接口客户端（session + SSE 流式解析）
│   │   ├── crypto.dart            会话签名（clientSign）等加密封装
│   │   ├── models.dart            数据模型（ApiSession / ConvertEvent / ConvertResult…）
│   │   ├── gopeed_engine.dart     Gopeed 引擎桥接（MethodChannel / 子进程 + REST）
│   │   ├── download_manager.dart  下载任务管理层（ChangeNotifier 单例，轮询同步进度）
│   │   ├── storage_service.dart   下载目录解析、持久化与存储权限编排
│   │   └── startup_hooks.dart     启动钩子扩展点（StartupHooks）
│   ├── theme/app_theme.dart       调色板与亮 / 暗主题
│   └── ui/
│       ├── home_page.dart         首页（粘贴链接、解析进度、结果卡片、公告）
│       └── downloads_page.dart    下载任务列表
├── android/                       Android 工程
│   └── app/src/main/kotlin/com/baidujiexi/baidujiexi_app/
│       ├── MainActivity.kt        入口 Activity（转发权限回调）
│       ├── GopeedBridge.kt        Gopeed 引擎 MethodChannel 桥
│       └── StorageBridge.kt       存储目录 / 权限 MethodChannel 桥
├── windows/                       Windows 工程（内嵌 gopeed-rest.exe）
├── ios/                           iOS 工程骨架
└── test/core_test.dart            核心逻辑单元测试
```

---

## 快速开始

环境要求：Flutter 3.x（Dart SDK `^3.12.2`）。

```bash
flutter pub get

# 运行（连接设备 / 桌面）
flutter run

# 校验
flutter analyze   # 需 0 issue
flutter test      # 单元测试全绿
```

---

## 构建

```bash
# Android（推荐只打包 arm64，见「Android 打包约定」）
flutter build apk --release --target-platform android-arm64

# Windows
flutter build windows --release
```

产物位置：

- Android：`build/app/outputs/flutter-apk/app-release.apk`
- Windows：`build/windows/x64/runner/Release/`

### 指定 bootstrap 地址

默认 bootstrap 地址定义在 [remote_config.dart](file:///d:/phpstudy_pro/WWW/hhh.com/baidujiexi_app/lib/core/remote_config.dart) 的 `kDefaultBootstrapUrls`。可在构建时覆盖：

```bash
flutter build apk --release \
  --dart-define=BOOTSTRAP_URL=https://your.domain/api/app/config.php
```

---

## 架构说明

### 1. 远端配置（`remote_config.dart`）

App 启动时按顺序请求 bootstrap 地址，直到拿到一份合法配置，并写入 `shared_preferences` 缓存；后续启动优先使用缓存，网络不可达时仍可工作。

`AppConfig` 字段：

| 字段 | 含义 |
| --- | --- |
| `apiBase` | 转换接口基础地址（无尾斜杠） |
| `siteOrigin` | 注入请求头 `Origin`，上游据此校验会话归属 |
| `referer` | 注入请求头 `Referer` |
| `fallbackBases` | 主地址失败时依次尝试的备用地址 |
| `defaultMode` | 默认转换模式：`web`（直链）/ `exe`（PC 下载器） |
| `configVersion` | 后端下发的版本号，用于识别缓存是否过期 |
| `announcement` | 首页公告文案，空字符串表示隐藏 |
| `extras` | 未被显式建模的其余键，原样保留，可用 `extra<T>(key)` 读取 |

> 除 bootstrap 地址外，**其余所有网络配置都由后端下发**，运营方迁移域名无需重新发版。

### 2. 转换接口（`api_client.dart`）

流程分两步：

1. `GET /api/session` → `{ token, secret, ttl }`
   - 必须用 **GET**；
   - `secret` 仅用于本地签名，不上行；
   - 会话按 `ttl` 缓存并预留 1 分钟安全边界。
2. `POST /api/downloadConvertUrl`（SSE，`Accept: text/event-stream`）
   - 请求头：`Origin` / `Referer` / `User-Agent`，以及 `x-session-token`、`x-client-sign`；
   - body：`{ "link": <规范化链接>, "mode": "web|exe", "ref": <referer> }`；
   - `x-client-sign = clientSign(secret, link)`，**只对规范化后的链接字符串加签**（不是整个 JSON body）。

分享链接会被 `normalizeShareLink()` 规范化为 `https://pan.baidu.com/s/1<surl>?pwd=<提取码>`。提取码可来自链接中的 `?pwd=`，也可来自粘贴文本里的 `提取码：xxxx`；签名必须覆盖这个规范化后的完整字符串。

SSE 事件逐步返回（`step` 字段）：`queue` / `ready` / `link_check` / `verify_pwd` / `file_list` / `import` / `wait_import` / `batch_download` / `batch_progress` / `done`；错误帧 `error != 0`。

`convertToResult()` 会把整段事件流聚合成一个 `ConvertResult`（`links` / `exeUrls` / `tokens`），并通过 `onEvent` 回调把每一帧透出给 UI 展示进度。

### 3. 下载引擎（`gopeed_engine.dart`）

单例桥接层，启动幂等并带存活自愈：已启动时先探测引擎是否仍可达，不可达则复位后完整重启，避免请求命中死端口。

- **Android / iOS**：`MethodChannel('com.baidujiexi.baidujiexi_app/gopeed')`，原生实现见 [GopeedBridge.kt](file:///d:/phpstudy_pro/WWW/hhh.com/baidujiexi_app/android/app/src/main/kotlin/com/baidujiexi/baidujiexi_app/GopeedBridge.kt)，入口类 `com.gopeed.mobile.Mobile`（依赖 `libgopeed.aar`）。
- **Windows**：以子进程方式拉起 `gopeed-rest.exe`，从 stdout 解析 `GOPEED_PORT=<port>`（超时 20s），错误行以 `GOPEED_ERROR=` 前缀输出。

启动后统一通过 `http://127.0.0.1:<port>/api/v1` 访问 Gopeed REST API：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/tasks` | 创建下载任务 |
| `GET` | `/tasks` | 任务列表 |
| `PUT` | `/tasks/{id}/pause` \| `/continue` | 暂停 / 继续 |
| `DELETE` | `/tasks/{id}?force=true` | 删除（`force` 连文件一起删） |

响应统一为 `{ code, msg, data }`，`code == 0` 表示成功；任务状态机为 `ready` / `running` / `wait` / `pause` / `error` / `done`。

### 4. 下载任务管理（`download_manager.dart`）

`DownloadManager` 是 `ChangeNotifier` 单例，以 800ms 间隔轮询引擎任务列表并同步进度到 UI，把引擎状态映射为 `DownloadStatus`（`ready` / `running` / `waiting` / `paused` / `error` / `done`）。

### 5. 下载目录与存储权限（`storage_service.dart`）

目录解析优先级：

1. 用户自定义目录（`shared_preferences` 键 `download_dir_custom`，校验可写后生效）
2. 系统公共下载目录 `/storage/emulated/0/Download/`
3. 应用专属外部目录兜底（无需权限，恒可写）

原生桥 `MethodChannel('com.baidujiexi.baidujiexi_app/storage')` 提供 `getDefaultDir` / `getFallbackDir` / `hasPermission` / `requestPermission` / `ensureDir`（写探针校验可写性），实现见 [StorageBridge.kt](file:///d:/phpstudy_pro/WWW/hhh.com/baidujiexi_app/android/app/src/main/kotlin/com/baidujiexi/baidujiexi_app/StorageBridge.kt)；运行时权限回调由 `MainActivity.onRequestPermissionsResult` 转发。

Android 版本与权限矩阵：

| Android 版本 | API | 写公共目录所需 |
| --- | --- | --- |
| 7–9 | 24–28 | 运行时授予 `WRITE_EXTERNAL_STORAGE` |
| 10 | 29 | `requestLegacyExternalStorage="true"` + 上述权限 |
| 11–16 | 30–36 | `MANAGE_EXTERNAL_STORAGE`（「所有文件访问」，需跳系统设置页手动开启） |

Manifest 中相应权限均带 `maxSdkVersion` 声明（见 [AndroidManifest.xml](file:///d:/phpstudy_pro/WWW/hhh.com/baidujiexi_app/android/app/src/main/AndroidManifest.xml)）。

> 切换目录无需重启引擎：Gopeed 的 `createTask(opts.path)` 支持每任务指定路径，改目录时失效 `DownloadManager` 的目录缓存即可，后续新任务自动使用新目录。

### 6. 启动钩子扩展点（`startup_hooks.dart`）

`StartupHooks.register(...)` 允许在 `runApp` 之前注册一个在启动后执行一次的回调（例如需要弹窗、上报等副作用）。钩子在远端配置解析完成、首页首帧绘制之后触发，因此持有挂载在 `MaterialApp` 下的 `BuildContext`，可安全弹出对话框；单个钩子抛错会被隔离记录，不影响 App 启动。

---

## 后端配置接口

配置由站点后端下发，示例见仓库同级的 `api/app/config.json` 与 `api/app/config.php`：

```json
{
  "apiBase": "https://file.mdx.wang",
  "siteOrigin": "https://file.mdx.wang",
  "referer": "https://file.mdx.wang/",
  "fallbackBases": [],
  "defaultMode": "web",
  "configVersion": 1,
  "announcement": "欢迎使用网盘直链助手！"
}
```

- `announcement` 为空字符串时，首页公告卡片整块隐藏。
- 修改公告后，重新请求配置接口或重启 App 即可生效。

---

## Android 打包约定

Gopeed 引擎的 `libgopeed.aar` 只包含 arm64-v8a 预编译产物，因此统一只打包 arm64：

```bash
flutter build apk --release --target-platform android-arm64
```

关键配置（`android/app/build.gradle.kts`）：

- `ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }`
  必须 **先 `clear()` 再 `add()`**，否则 AAR 内其他 ABI 的 `libgojni.so` 会被一并打进 APK（体积从约 26 MB 膨胀到 55 MB+）。
- release 构建需同时 `isMinifyEnabled = false` 与 `isShrinkResources = false`
  只关混淆不关资源压缩会报 `Removing unused resources requires unused code shrinking to be turned on`。
- `packaging { jniLibs { useLegacyPackaging = true } }`
  引擎 `.so` 需解压到磁盘后再加载。

---

## 内置二进制产物

以下文件随仓库提供，以便直接构建运行：

| 文件 | 用途 |
| --- | --- |
| `android/app/libs/libgopeed.aar` | Android Gopeed 引擎（含 `libgojni.so`） |
| `android/app/src/main/jniLibs/arm64-v8a/libc++_shared.so` | Go 引擎所需 C++ 运行库 |
| `windows/runner/gopeed-rest.exe` | Windows Gopeed 引擎子进程 |

Windows 端由 `windows/runner/CMakeLists.txt` 的 POST_BUILD 规则自动把 `gopeed-rest.exe` 拷贝到可执行文件同级目录。

---

## 依赖

见 [pubspec.yaml](file:///d:/phpstudy_pro/WWW/hhh.com/baidujiexi_app/pubspec.yaml)：

- `http` —— 会话请求与 SSE 流式转换
- `shared_preferences` —— 远端配置与下载目录的本地缓存
- `url_launcher` —— 用系统浏览器 / 下载器打开直链
- `path` / `path_provider` —— 路径处理与平台目录获取
- `cupertino_icons` —— iOS 风格图标

---

## 测试

```bash
flutter test
```

`test/core_test.dart` 覆盖核心逻辑：分享链接规范化、SSE 帧解析、配置解析与 `extras` 透传、下载目录解析与持久化、签名计算等。
