import 'package:flutter/material.dart';

/// 全局颜色表：根据当前亮度模式（浅色/深色）动态返回对应颜色。
///
/// 由 [AppTheme] / 主题切换时调用 [AppColors.setBrightness] 同步。
abstract final class AppColors {
  static Brightness _brightness = Brightness.light;

  /// 切换亮度模式（浅色/深色）
  static void setBrightness(Brightness value) {
    _brightness = value;
  }

  static Brightness get brightness => _brightness;

  // ---------------- 浅色调色板 ----------------
  static const _lightBackground = Color(0xFFF3F4F8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceHigh = Color(0xFFE9ECF3);
  static const _lightSurfaceSoft = Color(0xFFE4E7EF);
  static const _lightBorder = Color(0xFFC9D0DD);
  static const _lightPrimarySoft = Color(0xFFDCECFF);
  static const _lightTextPrimary = Color(0xFF1A1B23);
  static const _lightTextSecondary = Color(0xFF5D6170);
  static const _lightTextMuted = Color(0xFF9AA0AE);

  // ---------------- 深色调色板 ----------------
  static const _darkBackground = Color(0xFF1B1A20);
  static const _darkSurface = Color(0xFF24232B);
  static const _darkSurfaceHigh = Color(0xFF2C2B34);
  static const _darkSurfaceSoft = Color(0xFF34333D);
  static const _darkBorder = Color(0xFF3B3A45);
  static const _darkPrimarySoft = Color(0xFF103B60);
  static const _darkTextPrimary = Color(0xFFF8F8FA);
  static const _darkTextSecondary = Color(0xFFB1B0BA);
  static const _darkTextMuted = Color(0xFF777681);

  // ---------------- 语义色 ----------------
  static const _lightWarning = Color(0xFFE8932E);
  static const _lightDanger = Color(0xFFE24E59);
  static const _lightSuccess = Color(0xFF1FA86E);
  static const _lightSecondary = Color(0xFF0A7BD8);

  // ---------------- 对外颜色接口 ----------------
  static Color get background =>
      _brightness == Brightness.dark ? _darkBackground : _lightBackground;
  static Color get surface =>
      _brightness == Brightness.dark ? _darkSurface : _lightSurface;
  static Color get surfaceHigh =>
      _brightness == Brightness.dark ? _darkSurfaceHigh : _lightSurfaceHigh;
  static Color get surfaceSoft =>
      _brightness == Brightness.dark ? _darkSurfaceSoft : _lightSurfaceSoft;
  static Color get border =>
      _brightness == Brightness.dark ? _darkBorder : _lightBorder;
  static const Color primary = Color(0xFF0A8CFF);
  static Color get primarySoft =>
      _brightness == Brightness.dark ? _darkPrimarySoft : _lightPrimarySoft;
  static Color get secondary =>
      _brightness == Brightness.dark ? const Color(0xFF62B7FF) : _lightSecondary;
  static Color get warning =>
      _brightness == Brightness.dark ? const Color(0xFFFFB454) : _lightWarning;
  static Color get danger =>
      _brightness == Brightness.dark ? const Color(0xFFFF6B75) : _lightDanger;
  static Color get success =>
      _brightness == Brightness.dark ? const Color(0xFF57D6A0) : _lightSuccess;
  static Color get textPrimary =>
      _brightness == Brightness.dark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary =>
      _brightness == Brightness.dark ? _darkTextSecondary : _lightTextSecondary;
  static Color get textMuted =>
      _brightness == Brightness.dark ? _darkTextMuted : _lightTextMuted;
}

abstract final class AppTheme {
  static ThemeData get light {
    AppColors.setBrightness(Brightness.light);
    // 完整显式声明 M3 全部角色色：仅设 primary/secondary 时，其余角色会回落到
    // Material 基线（偏紫/粉）的默认值，导致 FilledButton、Dialog、Switch、
    // NavigationBar 等组件出现与蓝色主色不协调的杂色。
    final scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD6E9FF),
      onPrimaryContainer: const Color(0xFF00315C),
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDCEAF9),
      onSecondaryContainer: const Color(0xFF0B2A45),
      tertiary: const Color(0xFF2E9E8F),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFCCEFEB),
      onTertiaryContainer: const Color(0xFF063B36),
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: const Color(0xFFFBDDE0),
      onErrorContainer: const Color(0xFF5F1418),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF7F8FB),
      surfaceContainer: const Color(0xFFF0F2F7),
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceSoft,
      outline: AppColors.border,
      outlineVariant: const Color(0xFFDDE2EB),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: const Color(0xFF2C2B34),
      onInverseSurface: const Color(0xFFF8F8FA),
      inversePrimary: const Color(0xFF62B7FF),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(AppColors.textPrimary),
      dividerColor: AppColors.border,
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: _cardTheme(),
      inputDecorationTheme: _inputDecoration(),
      filledButtonTheme: _filledButton(),
      outlinedButtonTheme: _outlinedButton(),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          highlightColor: AppColors.primarySoft,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      snackBarTheme: _snackBar(),
    );
  }

  static ThemeData get dark {
    AppColors.setBrightness(Brightness.dark);
    final scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF103B60),
      onPrimaryContainer: const Color(0xFFD6E9FF),
      secondary: const Color(0xFF62B7FF),
      onSecondary: const Color(0xFF05233C),
      secondaryContainer: const Color(0xFF143350),
      onSecondaryContainer: const Color(0xFFCFE5FF),
      tertiary: const Color(0xFF57D6C7),
      onTertiary: const Color(0xFF04352F),
      tertiaryContainer: const Color(0xFF12463F),
      onTertiaryContainer: const Color(0xFFCCEFEB),
      error: const Color(0xFFFF6B75),
      onError: const Color(0xFF3D0A0E),
      errorContainer: const Color(0xFF5A1A20),
      onErrorContainer: const Color(0xFFFBDDE0),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: const Color(0xFF151419),
      surfaceContainerLow: const Color(0xFF1F1E25),
      surfaceContainer: const Color(0xFF24232B),
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceSoft,
      outline: AppColors.border,
      outlineVariant: const Color(0xFF33323C),
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: const Color(0xFFF8F8FA),
      onInverseSurface: const Color(0xFF2C2B34),
      inversePrimary: const Color(0xFF0A7BD8),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(AppColors.textPrimary),
      dividerColor: AppColors.border,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: _cardTheme(),
      inputDecorationTheme: _inputDecoration(),
      filledButtonTheme: _filledButton(),
      outlinedButtonTheme: _outlinedButton(),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          highlightColor: AppColors.primarySoft,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      snackBarTheme: _snackBar(),
    );
  }

  static TextTheme _textTheme(Color bodyColor) {
    return const TextTheme(
      displaySmall: TextStyle(
        fontSize: 27,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        fontSize: 23,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ).apply(
      bodyColor: bodyColor,
      displayColor: bodyColor,
    );
  }

  static CardThemeData _cardTheme() {
    return CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.border),
      ),
    );
  }

  static InputDecorationTheme _inputDecoration() {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: AppColors.border),
      ),
    );
  }

  static FilledButtonThemeData _filledButton() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceSoft,
        disabledForegroundColor: AppColors.textMuted,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButton() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  static SnackBarThemeData _snackBar() {
    return SnackBarThemeData(
      backgroundColor: AppColors.surfaceSoft,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}
