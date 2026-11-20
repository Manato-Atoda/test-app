import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 画面の広さに合わせたレイアウトの決まりごと。
///
/// iPhone 11 のような幅の狭い画面から、iPhone Duo を開いたときの横長の画面まで対応する。
/// 機種や向きではなく「いま使える幅」で決めるので、折りたたみの開閉や回転で幅が変わっても追従する。
/// 左右のセーフエリア（iPhone Duo の縦に並ぶステータスバー、横向きの iPhone のノッチなど）は
/// 左右それぞれの値をそのまま避ける。
abstract final class Adaptive {
  /// 2 列にし始める幅
  static const double medium = 600;

  /// 3 列にし始める幅
  static const double expanded = 900;

  /// 一覧の最大幅
  static const double listMaxWidth = 1040;

  /// 記事本文の最大幅（1 行が長くなりすぎないように）
  static const double readingMaxWidth = 680;

  /// フォームの最大幅
  static const double formMaxWidth = 520;

  /// 左右のセーフエリアを除いた、使える幅
  static double usableWidth(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return MediaQuery.sizeOf(context).width - padding.left - padding.right;
  }

  /// カードを並べる列数
  static int columns(BuildContext context) {
    final width = usableWidth(context);
    if (width >= expanded) return 3;
    if (width >= medium) return 2;
    return 1;
  }

  /// 内容を中央の [maxWidth] に収め、左右のセーフエリアを避ける余白。
  /// [gutter] は画面の端から内容までの余白。
  static EdgeInsets horizontal(BuildContext context, {double maxWidth = listMaxWidth, double gutter = 20}) {
    final padding = MediaQuery.paddingOf(context);
    final extra = math.max(0.0, usableWidth(context) - gutter * 2 - maxWidth) / 2;
    return EdgeInsets.only(left: padding.left + gutter + extra, right: padding.right + gutter + extra);
  }
}

/// 子を [columns] 列に並べた 1 行。行の中のカードは高さをそろえる。
class GridRow extends StatelessWidget {
  const GridRow({super.key, required this.columns, required this.children, this.spacing = 18});

  final int columns;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (columns == 1 && children.length == 1) return children.single;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: i < children.length ? children[i] : const SizedBox.shrink()),
          ],
        ],
      ),
    );
  }

  /// [items] を [columns] 個ずつの行に分ける
  static List<List<T>> chunk<T>(List<T> items, int columns) => [
        for (var i = 0; i < items.length; i += columns) items.sublist(i, math.min(i + columns, items.length)),
      ];
}

/// 子を [columns] 列のグリッドに並べる（一覧が短い画面向け）。
class GridColumn extends StatelessWidget {
  const GridColumn({super.key, required this.columns, required this.children, this.spacing = 18, double? runSpacing})
      : runSpacing = runSpacing ?? spacing;

  final int columns;
  final List<Widget> children;

  /// 横の間隔
  final double spacing;

  /// 行と行の間隔
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    final rows = GridRow.chunk(children, columns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: runSpacing),
          GridRow(columns: columns, spacing: spacing, children: rows[i]),
        ],
      ],
    );
  }
}
