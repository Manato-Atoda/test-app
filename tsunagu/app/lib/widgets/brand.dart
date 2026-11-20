import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// ロゴ「M」（ブランドのグラデーションの角丸）。
class MLogo extends StatelessWidget {
  const MLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [BoxShadow(color: const Color(0x406366F1), blurRadius: size * 0.4, offset: Offset(0, size * 0.1))],
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.56,
          height: 1,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// グラデーションの文字（「M」の見出しなど）。
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.gradient = brandGradient});

  final String text;
  final TextStyle? style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style),
    );
  }
}

/// Galaxia の主要ボタン（indigo → violet → purple のカプセル＋影）。
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 18, color: Colors.white),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled || busy ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: buttonGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled ? const [BoxShadow(color: Color(0x406366F1), blurRadius: 12, offset: Offset(0, 4))] : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: height,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// オーロラの背景（上・右・左の淡い放射グラデーション）。中身の後ろに敷く。
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.background),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _AuroraPainter(p.auroraTop, p.auroraRight, p.auroraLeft)),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.top, this.right, this.left);

  final Color top;
  final Color right;
  final Color left;

  void _ellipse(Canvas canvas, Size size, Offset center, double rx, double ry, Color color) {
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)], stops: const [0, 0.6]).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // globals.css の --gradient-aurora に合わせた 3 つの楕円
    _ellipse(canvas, size, Offset(w * 0.5, -h * 0.1), w * 0.8, h * 0.5, top);
    _ellipse(canvas, size, Offset(w, h * 0.3), w * 0.6, h * 0.4, right);
    _ellipse(canvas, size, Offset(0, h * 0.6), w * 0.6, h * 0.4, left);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.top != top || old.right != right || old.left != left;
}

/// 小さなカプセルのラベル（チャンネル・発信者の種類など）。
class TagPill extends StatelessWidget {
  const TagPill(this.text, {super.key, this.color, this.background, this.onTap, this.small = false});

  final String text;
  final Color? color;
  final Color? background;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(
        color: background ?? p.accentSoft,
        borderRadius: BorderRadius.circular(small ? 4 : 999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: small ? 9.5 : 11,
          fontWeight: FontWeight.w700,
          color: color ?? p.accent,
          letterSpacing: small ? 0.4 : 0,
        ),
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: pill);
  }
}

/// 新着の赤い点（森は答え待ちの程度で色を変える）。
class NewDot extends StatelessWidget {
  const NewDot({super.key, this.color, this.size = 8});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.m.rose;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: size * 0.8)],
      ),
    );
  }
}

/// 件数のバッジ（99+ まで）。
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    // alignment を付けた Container は使える幅いっぱいに広がる（ListTile の右端に置くと行が崩れて白紙になる）ので、
    // Center の widthFactor で中身の幅に合わせる
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: context.m.rose, borderRadius: BorderRadius.circular(999)),
      child: Center(
        widthFactor: 1,
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Galaxia のカード（角丸 24・細い枠線・薄い影）。
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.accentBar});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// 左端の細い帯（お知らせ・未確認など）。
  final Color? accentBar;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surfaceElevated,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Padding(padding: padding, child: child),
                if (accentBar != null)
                  Positioned(
                    left: 0,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: accentBar,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 見出し（小さめの太字・muted）。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 8)});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.m.muted, letterSpacing: 0.2),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
