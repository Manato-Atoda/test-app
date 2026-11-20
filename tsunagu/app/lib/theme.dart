import 'package:material_ui/material_ui.dart';

/// Galaxia（参照デザイン）の色。globals.css の値をそのまま使う。
@immutable
class MPalette extends ThemeExtension<MPalette> {
  const MPalette({
    required this.background,
    required this.foreground,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.borderSoft,
    required this.muted,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.secondary,
    required this.secondarySoft,
    required this.highlight,
    required this.like,
    required this.likeSoft,
    required this.success,
    required this.warning,
    required this.auroraTop,
    required this.auroraRight,
    required this.auroraLeft,
  });

  static const light = MPalette(
    background: Color(0xFFFAFBFF),
    foreground: Color(0xFF0A0A0F),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    borderSoft: Color(0xFFF1F3F5),
    muted: Color(0xFF6B7280),
    accent: Color(0xFF6366F1),
    accentHover: Color(0xFF4F46E5),
    accentSoft: Color(0xFFEEF2FF),
    secondary: Color(0xFF06B6D4),
    secondarySoft: Color(0xFFECFEFF),
    highlight: Color(0xFFA855F7),
    like: Color(0xFFF43F5E),
    likeSoft: Color(0xFFFFF1F2),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    auroraTop: Color(0x266366F1), // rgba(99,102,241,0.15)
    auroraRight: Color(0x1AA855F7), // rgba(168,85,247,0.10)
    auroraLeft: Color(0x1A06B6D4), // rgba(6,182,212,0.10)
  );

  static const dark = MPalette(
    background: Color(0xFF050510),
    foreground: Color(0xFFFAFAFA),
    surface: Color(0xFF0D0D18),
    surfaceElevated: Color(0xFF131322),
    border: Color(0xFF1F1F2E),
    borderSoft: Color(0xFF161624),
    muted: Color(0xFF9CA3AF),
    accent: Color(0xFF818CF8),
    accentHover: Color(0xFF6366F1),
    accentSoft: Color(0x266366F1), // rgba(99,102,241,0.15)
    secondary: Color(0xFF22D3EE),
    secondarySoft: Color(0x1F22D3EE), // rgba(34,211,238,0.12)
    highlight: Color(0xFFC084FC),
    like: Color(0xFFFB7185),
    likeSoft: Color(0x26F43F5E), // rgba(244,63,94,0.15)
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    auroraTop: Color(0x406366F1), // 0.25
    auroraRight: Color(0x2EA855F7), // 0.18
    auroraLeft: Color(0x2622D3EE), // 0.15
  );

  final Color background;
  final Color foreground;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color borderSoft;
  final Color muted;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color secondary;
  final Color secondarySoft;
  final Color highlight;
  final Color like;
  final Color likeSoft;
  final Color success;
  final Color warning;
  final Color auroraTop;
  final Color auroraRight;
  final Color auroraLeft;

  /// 新着・未読の赤（Tailwind rose-500）。
  Color get rose => const Color(0xFFF43F5E);

  @override
  MPalette copyWith() => this;

  @override
  MPalette lerp(ThemeExtension<MPalette>? other, double t) => t < 0.5 ? this : (other as MPalette? ?? this);
}

/// ブランドのグラデーション（135°: indigo → violet → cyan）。ロゴ・カバーの既定に使う。
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF06B6D4)],
);

/// 主要ボタンのグラデーション（indigo-500 → violet-500 → purple-600）。
const buttonGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF9333EA)],
);

extension MThemeContext on BuildContext {
  MPalette get m => Theme.of(this).extension<MPalette>() ?? MPalette.light;
}

/// Windows では既定フォントに日本語がないため、日本語フォントを順に試す。
const _fontFallback = <String>['Hiragino Sans', 'Yu Gothic UI', 'Meiryo', 'Noto Sans JP', 'Noto Sans CJK JP'];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.light ? MPalette.light : MPalette.dark;
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1), brightness: brightness).copyWith(
    primary: p.accent,
    onPrimary: Colors.white,
    primaryContainer: p.accentSoft,
    onPrimaryContainer: p.accent,
    secondary: p.secondary,
    tertiary: p.highlight,
    surface: p.surface,
    onSurface: p.foreground,
    onSurfaceVariant: p.muted,
    outline: p.border,
    outlineVariant: p.borderSoft,
    surfaceContainerLowest: p.surfaceElevated,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.borderSoft,
    surfaceContainerHighest: p.borderSoft,
    error: const Color(0xFFDC2626),
  );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  return base.copyWith(
    extensions: [p],
    textTheme: base.textTheme.apply(
      fontFamilyFallback: _fontFallback,
      bodyColor: p.foreground,
      displayColor: p.foreground,
    ),
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.border,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: p.foreground,
        fontFamilyFallback: _fontFallback,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: p.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        backgroundColor: p.accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        foregroundColor: p.muted,
        side: BorderSide(color: p.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, shape: pill),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: pill,
      side: BorderSide(color: p.border),
      backgroundColor: p.surfaceElevated,
      selectedColor: p.accentSoft,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.muted),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceElevated,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
  );
}

/// アバターの 8 色（サーバーの avatar_color 0〜7）。
const avatarPalette = <Color>[
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF64748B),
  Color(0xFFEF4444),
];
