import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/vamos_theme.dart';
import 'adaptive.dart';

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

/// 下部のタブバー。
///
/// リキッドグラスが使える iOS では、iOS 本物の UITabBar を使う（選択のレンズが滑る・
/// 押すと反応する・指でなぞって切り替える、といった動きは iOS 標準のもの）。
/// それ以外の環境では、Vamos デザインの浮いたカプセル型タブバーを Flutter で描く。
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    // 左右のセーフエリア（iPhone Duo の縦のステータスバーなど）には重ねない
    final safeArea = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSupport.available,
      builder: (context, available, _) => available
          ? Padding(
              padding: EdgeInsets.only(left: safeArea.left, right: safeArea.right),
              child: _NativeTabBar(items: items, selectedIndex: selectedIndex, onSelected: onSelected),
            )
          : _buildFlutterTabBar(context),
    );
  }

  Widget _buildFlutterTabBar(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // 広い画面ではカプセルが横に間延びしないよう、幅を抑えて中央に置く
    return Padding(
      padding: Adaptive.horizontal(context, maxWidth: 480, gutter: 16).copyWith(bottom: bottom > 0 ? bottom - 6 : 12),
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
  const GlassTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.symbol,
    required this.selectedSymbol,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// iOS の SF Symbols の名前（本物のタブバーで使う）
  final String symbol;
  final String selectedSymbol;
}

/// iOS 本物の UITabBar（AppDelegate.swift の VamosTabBarView）
class _NativeTabBar extends StatefulWidget {
  const _NativeTabBar({required this.items, required this.selectedIndex, required this.onSelected});

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<_NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<_NativeTabBar> {
  MethodChannel? _channel;

  void _onCreated(int id) {
    final channel = MethodChannel('vamos/tabbar/$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSelect' && call.arguments is int) widget.onSelected(call.arguments as int);
    });
    _channel = channel;
  }

  @override
  void didUpdateWidget(covariant _NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _channel?.invokeMethod<void>('select', widget.selectedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 62 + bottom,
      child: UiKitView(
        viewType: 'vamos/tabbar',
        creationParams: <String, Object?>{
          'selected': widget.selectedIndex,
          'tint': VamosColors.primary.toARGB32(),
          'items': [
            for (final item in widget.items)
              {'title': item.label, 'symbol': item.symbol, 'selectedSymbol': item.selectedSymbol},
          ],
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        // タブバーへの指の動き（なぞる操作を含む）は、すべて iOS 側で受ける
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
    );
  }
}

/// アイコンだけのボタン。リキッドグラスが使える iOS では、押すとガラスが反応する
/// iOS 本物のボタン（UIButton のガラス）を使う。
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    required this.symbol,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  /// iOS の SF Symbols の名前
  final String symbol;

  /// リキッドグラスが使えないときのアイコン
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  void _onCreated(int id) {
    MethodChannel('vamos/glassbutton/$id').setMethodCallHandler((call) async {
      if (call.method == 'onTap') widget.onPressed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSupport.available,
      builder: (context, available, _) {
        if (!available || widget.onPressed == null) {
          return IconButton(
            tooltip: widget.tooltip,
            icon: Icon(widget.icon, color: widget.color),
            onPressed: widget.onPressed,
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 40,
            height: 40,
            child: UiKitView(
              // 記号や色が変わったら、ボタンを作り直す（保存のオン・オフなど）
              key: ValueKey('${widget.symbol}-${widget.color?.toARGB32()}'),
              viewType: 'vamos/glassbutton',
              creationParams: <String, Object?>{
                'symbol': widget.symbol,
                'label': widget.tooltip,
                if (widget.color != null) 'tint': widget.color!.toARGB32(),
              },
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onCreated,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
              },
            ),
          ),
        );
      },
    );
  }
}

/// ヘッダーの背景。iOS 26 の「スクロールエッジ効果」と同じく、下を流れる内容を
/// すりガラス状にぼかす（ボタンはガラス、背景はぼかし、という iOS 標準の組み合わせ）。
/// リキッドグラスが使えない環境では白い面で表示する。
class ScrollEdgeBackground extends StatelessWidget {
  const ScrollEdgeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSupport.available,
      builder: (context, available, _) {
        if (!available) return const ColoredBox(color: VamosColors.surface);
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: ColoredBox(color: VamosColors.background.withValues(alpha: 0.72)),
          ),
        );
      },
    );
  }
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

/// 詳細画面用の上部バー（Scaffold の extendBodyBehindAppBar と組み合わせる）。
/// 戻る・共有などのボタンはガラス、背景はスクロールエッジ効果。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.actions = const [], this.showBack = true});

  final Widget? title;
  final List<Widget> actions;

  /// 戻るボタンを出す（2 画面表示の右側に置くときは false）
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();
    return AppBar(
      title: title,
      actions: actions,
      automaticallyImplyLeading: false,
      leadingWidth: 60,
      leading: canPop
          ? Center(
              child: GlassIconButton(
                symbol: 'chevron.left',
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '戻る',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      // AppBar は flexibleSpace に高さを指定しないので、広げないと背景が高さ 0 になり描かれない
      flexibleSpace: const SizedBox.expand(child: ScrollEdgeBackground()),
    );
  }
}
