import 'package:flutter/material.dart';

/// RE_VAMOS の style.css（:root）に合わせた色。
abstract final class VamosColors {
  static const background = Color(0xFFEEF1F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF4F6FA);
  static const text = Color(0xFF1A1A1A);
  static const textMuted = Color(0xFF5C6370);
  static const textLight = Color(0xFF8E95A3);
  static const border = Color(0xFFD8DDE6);
  static const borderLight = Color(0xFFE8ECF2);
  static const primary = Color(0xFF1B96D8);
  static const primaryLight = Color(0xFFE7F5FC);
  static const ctaBand = Color(0xFFDFE6EF);

  /// 装飾用の水色グラデーション
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5CC8F0), Color(0xFF2B8FE0)],
  );

  /// 白文字を載せるボタン用のグラデーション
  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2BA8E8), Color(0xFF1F80CF)],
  );
}

abstract final class VamosRadius {
  static const small = 6.0;
  static const medium = 8.0;
  static const large = 12.0;
}

abstract final class VamosShadows {
  static const card = [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const glow = [
    BoxShadow(color: Color(0x401B96D8), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

ThemeData buildVamosTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: VamosColors.primary,
      primary: VamosColors.primary,
      surface: VamosColors.surface,
    ),
    scaffoldBackgroundColor: VamosColors.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: VamosColors.text,
      displayColor: VamosColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VamosColors.surface,
      foregroundColor: VamosColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VamosColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: VamosColors.primaryLight,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? VamosColors.primary : VamosColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? VamosColors.primary : VamosColors.textMuted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: VamosColors.borderLight, thickness: 1, space: 1),
  );
}
