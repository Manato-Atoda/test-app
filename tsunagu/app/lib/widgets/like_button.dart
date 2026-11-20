import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// ハートのいいね。押すと弾み、「+1」が浮かぶ（誰が押したかは出さない）。
class LikeButton extends StatefulWidget {
  const LikeButton({super.key, required this.liked, required this.count, required this.onToggle, this.compact = false});

  final bool liked;
  final int count;

  /// 押されたとき（親がサーバーに送り、結果で [liked] / [count] を更新する）。
  final VoidCallback? onToggle;
  final bool compact;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  // heart-pop: 1 → 1.4（-8°）→ 0.92 → 1
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.4), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.92), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.92, end: 1), weight: 40),
  ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

  @override
  void dispose() {
    _pop.dispose();
    _float.dispose();
    super.dispose();
  }

  void _tap() {
    if (widget.onToggle == null) return;
    if (!widget.liked) {
      _pop.forward(from: 0);
      _float.forward(from: 0);
    }
    widget.onToggle!();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final color = widget.liked ? p.like : p.muted;
    return Semantics(
      button: true,
      toggled: widget.liked,
      label: 'いいね ${widget.count}',
      child: InkWell(
        onTap: widget.onToggle == null ? null : _tap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 6 : 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pop,
                      builder: (context, child) => Transform.rotate(
                        angle: _pop.isAnimating && _pop.value < 0.5 ? -0.14 * (_pop.value * 2) : 0,
                        child: Transform.scale(scale: _scale.value, child: child),
                      ),
                      child: Icon(
                        widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: widget.compact ? 18 : 20,
                        color: color,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _float,
                      builder: (context, _) {
                        if (!_float.isAnimating) return const SizedBox.shrink();
                        final t = _float.value;
                        final opacity = t < 0.2 ? t / 0.2 : (1 - t) / 0.8;
                        return Positioned(
                          top: -10 - 32 * t,
                          child: Opacity(
                            opacity: opacity.clamp(0, 1),
                            child: Transform.scale(
                              scale: 0.6 + 0.45 * t,
                              child: Text(
                                '+1',
                                style: TextStyle(color: p.like, fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: color,
                    fontSize: widget.compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
