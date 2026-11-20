import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_scope.dart';

/// スマホで画面全体に「氏名 / 社員コード」を斜めに薄く繰り返す（スクリーンショットの持ち出し対策）。
/// 企業設定（company.features.watermark）がオンで、iOS / Android のときだけ。操作は下に通す。
class Watermark extends StatelessWidget {
  const Watermark({super.key, required this.child});

  final Widget child;

  static bool get _isMobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.me;
    final on = state.company?.features.watermark ?? false;
    if (!on || me == null || !_isMobile) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WatermarkPainter(
                  '${me.displayName} / ${me.employeeCode}',
                  dark ? const Color(0x14FFFFFF) : const Color(0x120A0A0F),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter(this.label, this.color);

  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 7);
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final stepX = painter.width + 56;
    const stepY = 84.0;
    var row = 0;
    for (var y = -diag / 2; y < diag / 2; y += stepY) {
      final offset = (row.isEven ? 0 : stepX / 2);
      for (var x = -diag / 2 - offset; x < diag / 2; x += stepX) {
        painter.paint(canvas, Offset(x, y));
      }
      row++;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter old) => old.label != label || old.color != color;
}
