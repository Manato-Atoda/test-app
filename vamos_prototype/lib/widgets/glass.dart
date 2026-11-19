import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/vamos_theme.dart';

/// iOS のリキッドグラスを使えるか（iOS 26 以降で「透明度を下げる」がオフ）。
///
/// 使えない環境（Android・古い iOS・透明度を下げる設定）では、
/// 今までの Vamos デザイン（白い面＋影）で表示する。
abstract final class GlassSupport {
  static const _channel = MethodChannel('vamos/glass');

  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  static Future<void> init() async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSupportChanged') available.value = call.arguments == true;
    });
    await refresh();
  }

  static Future<void> refresh() async {
    if (!Platform.isIOS) return;
    try {
      available.value = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      available.value = false;
    }
  }
}

/// ガラスの面。リキッドグラスが使えるときは iOS のガラスを下に敷き、その上に child を描く。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.tint,
    this.fallbackColor = VamosColors.surface,
    this.fallbackShadow = VamosShadows.card,
    this.fallbackBorder = true,
  });

  final Widget child;
  final double borderRadius;

  /// ガラスにうっすら色をつける（例：Vamos の水色）
  final Color? tint;

  /// リキッドグラスが使えないときの背景
  final Color fallbackColor;
  final List<BoxShadow>? fallbackShadow;
  final bool fallbackBorder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSupport.available,
      builder: (context, available, _) {
        if (!available) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: fallbackColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: fallbackBorder ? Border.all(color: VamosColors.borderLight) : null,
              boxShadow: fallbackShadow,
            ),
            child: child,
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: UiKitView(
                viewType: 'vamos/glass',
                creationParams: <String, Object?>{
                  'cornerRadius': borderRadius,
                  if (tint != null) 'tint': tint!.toARGB32(),
                },
                creationParamsCodec: const StandardMessageCodec(),
                // タップは Flutter 側（上に描いたボタン）で受ける
                hitTestBehavior: PlatformViewHitTestBehavior.transparent,
                gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

/// iOS 26 風の浮いたタブバー（下部中央のカプセル）。
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom - 6 : 12),
      child: SizedBox(
        height: height,
        child: GlassSurface(
          borderRadius: height / 2,
          fallbackShadow: const [BoxShadow(color: Color(0x1F10203A), blurRadius: 24, offset: Offset(0, 8))],
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: [
                for (final (index, item) in items.indexed)
                  Expanded(
                    child: _GlassTabButton(
                      item: item,
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
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

class GlassTabItem {
  const GlassTabItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _GlassTabButton extends StatelessWidget {
  const _GlassTabButton({required this.item, required this.selected, required this.onTap});

  final GlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? VamosColors.primary : VamosColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            // 選択中のタブは、ガラスの上にうっすら水色のカプセルを重ねる
            color: selected ? VamosColors.primary.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(GlassTabBar.height / 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.selectedIcon : item.icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 詳細画面用のガラスの上部バー（Scaffold の extendBodyBehindAppBar と組み合わせる）
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions = const []});

  final Widget title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      flexibleSpace: const GlassSurface(
        fallbackShadow: null,
        fallbackBorder: false,
        child: SizedBox.expand(),
      ),
    );
  }
}
