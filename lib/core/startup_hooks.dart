/// Startup extension point.
///
/// The main app is open source and ships with **no** startup hooks
/// registered, so building `lib/main.dart` produces a plain app.
///
/// Optional modules living outside the open-source tree may register a hook
/// before `runApp`. Hooks run once, after the remote config has been resolved
/// and the first frame of the main screen is painted, so a hook can safely
/// show dialogs (it has a mounted [BuildContext] under `MaterialApp`).
///
/// A hook that throws is isolated: it is logged and ignored, never breaking
/// the app boot.
library;

import 'package:flutter/material.dart';

import 'remote_config.dart';

/// Signature of a startup hook.
///
/// [context] is a context mounted under `MaterialApp`; [config] is the
/// resolved remote config (use [AppConfig.extras] for module-private fields).
typedef StartupHook = Future<void> Function(BuildContext context, AppConfig config);

/// Registry of startup hooks. Empty by default.
class StartupHooks {
  StartupHooks._();

  static final List<StartupHook> _hooks = <StartupHook>[];

  /// Whether any hook has been registered.
  static bool get isEmpty => _hooks.isEmpty;

  /// Registers [hook] to run at startup. Safe to call multiple times.
  static void register(StartupHook hook) => _hooks.add(hook);

  /// Runs every registered hook once. Failures are swallowed per hook.
  static Future<void> run(BuildContext context, AppConfig config) async {
    for (final hook in List<StartupHook>.of(_hooks)) {
      try {
        await hook(context, config);
      } catch (error) {
        debugPrint('startup hook failed: $error');
      }
    }
  }
}
