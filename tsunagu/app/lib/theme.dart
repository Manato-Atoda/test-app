import 'package:material_ui/material_ui.dart';

const seedColor = Color(0xFF3355D1);

/// Windows では既定フォントに日本語がないため、日本語フォントを順に試す。
const _fontFallback = <String>[
  'Hiragino Sans',
  'Yu Gothic UI',
  'Meiryo',
  'Noto Sans JP',
  'Noto Sans CJK JP',
];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: _fontFallback),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF4F6FB)
        : scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: brightness == Brightness.light ? const Color(0xFFF4F6FB) : scheme.surface,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// アバターの 8 色（サーバーの avatar_color 0〜7）。
const avatarPalette = <Color>[
  Color(0xFF3355D1),
  Color(0xFF0F8B8D),
  Color(0xFF7A4CC2),
  Color(0xFFC2185B),
  Color(0xFFE07A1F),
  Color(0xFF2E7D32),
  Color(0xFF5D6B82),
  Color(0xFFB8860B),
];
