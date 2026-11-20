import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';

/// iOS のリキッドグラス（iOS 26 以降）を使えるか。
///
/// 使えるのは iOS 26 以降で、設定の「透明度を下げる」がオフのとき。
/// Android・macOS・Windows・古い iOS では今までどおりの Material のデザインで表示する。
abstract final class GlassSupport {
  static const _channel = MethodChannel('tsunagu/glass');

  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> init() async {
    if (!_isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSupportChanged') available.value = call.arguments == true;
    });
    try {
      available.value = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      available.value = false;
    }
  }
}

/// リキッドグラスの有無で作り分ける。
class GlassBuilder extends StatelessWidget {
  const GlassBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool glass) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSupport.available,
      builder: (context, glass, _) => builder(context, glass),
    );
  }
}

/// スクロールする一覧の余白。ガラスのバーの下に潜る画面では、上下のバーの高さぶんを足す。
/// （Scaffold の body の中の context で呼ぶこと）
EdgeInsets scrollPadding(BuildContext context, EdgeInsets base) {
  final inset = MediaQuery.paddingOf(context);
  return base.copyWith(top: base.top + inset.top, bottom: base.bottom + inset.bottom);
}

// ------------------------------------------------------------------ タブバー

class GlassTabItem {
  const GlassTabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.symbol,
    required this.selectedSymbol,
    this.badge = 0,
    this.dot = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// iOS の SF Symbols の名前（本物のタブバーで使う）
  final String symbol;
  final String selectedSymbol;

  /// 未読の数など（0 で非表示）
  final int badge;

  /// 数のない新着の印（赤い点）
  final bool dot;

  /// ネイティブに送るバッジ。'' はなし、'dot' は点だけ。
  String get badgeText => badge > 0 ? (badge > 99 ? '99+' : '$badge') : (dot ? 'dot' : '');
}

/// iOS 本物の UITabBar。選択の「レンズ」が滑る動き・押したときの反応・
/// 指でなぞって切り替える操作は、すべて iOS 標準の動きになる。
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.momentaryIndexes = const {},
  });

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 押しても選択を移さないタブ（メニューを開くだけ、など）。
  final Set<int> momentaryIndexes;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  MethodChannel? _channel;

  void _onCreated(int id) {
    final channel = MethodChannel('tsunagu/tabbar/$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onSelect' && call.arguments is int) {
        final index = call.arguments as int;
        widget.onSelected(index);
        if (widget.momentaryIndexes.contains(index)) {
          // 選択はもとのタブに戻す（ネイティブ側はすでに押したタブを選んでいる）
          channel.invokeMethod<void>('select', widget.selectedIndex);
        }
      }
    });
    _channel = channel;
  }

  @override
  void didUpdateWidget(covariant GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _channel?.invokeMethod<void>('select', widget.selectedIndex);
    }
    final badges = [for (final item in widget.items) item.badgeText];
    final oldBadges = [for (final item in oldWidget.items) item.badgeText];
    if (!listEquals(badges, oldBadges)) _channel?.invokeMethod<void>('setBadges', badges);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(left: inset.left, right: inset.right),
      child: SizedBox(
        height: GlassTabBarInset.tabBarHeight + inset.bottom,
        child: UiKitView(
          viewType: 'tsunagu/tabbar',
          creationParams: <String, Object?>{
            'selected': widget.selectedIndex,
            'tint': Theme.of(context).colorScheme.primary.toARGB32(),
            'items': [
              for (final item in widget.items)
                {'title': item.label, 'symbol': item.symbol, 'selectedSymbol': item.selectedSymbol},
            ],
            'badges': [for (final item in widget.items) item.badgeText],
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onCreated,
          // タブバーへの指の動き（なぞる操作を含む）は、すべて iOS 側で受ける
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      ),
    );
  }
}

/// ガラスのタブバーの高さ（ホームの安全領域を除く）を、タブの中の画面に伝える。
class GlassTabBarInset extends InheritedWidget {
  const GlassTabBarInset({super.key, required this.height, required super.child});

  static const tabBarHeight = 62.0;

  final double height;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassTabBarInset>()?.height ?? 0;

  @override
  bool updateShouldNotify(GlassTabBarInset oldWidget) => oldWidget.height != height;
}

// ------------------------------------------------------------------ ボタン

enum GlassButtonStyle {
  /// 透明なガラス（使えないときは TextButton / IconButton）
  plain,

  /// 色つきのガラス（使えないときは FilledButton）
  prominent,

  /// 透明なガラス（使えないときは OutlinedButton）
  outlined,
}

/// iOS 本物のガラスのボタン（押すとガラスが反応する）。
///
/// アイコンだけ（[symbol] と [icon]）、文字だけ（[label]）、両方、のどれでも使える。
/// リキッドグラスが使えないときは、[style] に合わせた Material のボタンになる。
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    this.label,
    this.symbol,
    this.icon,
    this.tooltip,
    required this.onPressed,
    this.style = GlassButtonStyle.plain,
    this.height = 44,
  }) : assert(label != null || (symbol != null && icon != null));

  final String? label;

  /// iOS の SF Symbols の名前
  final String? symbol;

  /// リキッドグラスが使えないときのアイコン
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final GlassButtonStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GlassBuilder(builder: (context, glass) => glass ? _native(context) : _fallback());
  }

  Widget _fallback() {
    final iconWidget = icon == null ? null : Icon(icon);
    if (label == null) {
      return IconButton(tooltip: tooltip, icon: iconWidget!, onPressed: onPressed);
    }
    final text = Text(label!);
    switch (style) {
      case GlassButtonStyle.prominent:
        return iconWidget == null
            ? FilledButton(onPressed: onPressed, child: text)
            : FilledButton.icon(onPressed: onPressed, icon: iconWidget, label: text);
      case GlassButtonStyle.outlined:
        return OutlinedButton(onPressed: onPressed, child: text);
      case GlassButtonStyle.plain:
        return iconWidget == null
            ? TextButton(onPressed: onPressed, child: text)
            : TextButton.icon(onPressed: onPressed, icon: iconWidget, label: text);
    }
  }

  /// 文字の幅から、ボタンの幅を見積もる（UIButton の左右の余白ぶんを足す）
  double _width(BuildContext context) {
    if (label == null) return height;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final iconWidth = symbol == null ? 0.0 : 24.0;
    return painter.width + iconWidth + 40;
  }

  Widget _native(BuildContext context) {
    final enabled = onPressed != null;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      // 上部バーの中では縦の中央に置き、右下のボタンとして置くときはボタンの大きさだけにする
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: _width(context),
          height: height,
          child: UiKitView(
            // 文字や有効・無効が変わったら作り直す
            key: ValueKey('$label|$symbol|$enabled|$style'),
            viewType: 'tsunagu/glassbutton',
            creationParams: <String, Object?>{
              'title': ?label,
              'symbol': ?symbol,
              'label': tooltip ?? label,
              'prominent': style == GlassButtonStyle.prominent,
              'enabled': enabled,
              if (style != GlassButtonStyle.plain || label != null) 'tint': primary.toARGB32(),
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (id) {
              MethodChannel('tsunagu/glassbutton/$id').setMethodCallHandler((call) async {
                if (call.method == 'onTap') onPressed?.call();
              });
            },
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            },
          ),
        ),
      ),
    );
  }
}

/// 「投稿」ボタン（右下）。リキッドグラスでは色つきのガラス、使えないときは Galaxia のグラデーションのカプセル。
class GlassComposeButton extends StatelessWidget {
  const GlassComposeButton({super.key, required this.onPressed, this.label = '投稿', this.symbol = 'square.and.pencil'});

  final VoidCallback onPressed;
  final String label;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    // 右下のボタンの位置はホームバーの高さしか考えないので、タブバーのぶん持ち上げる
    final inset = GlassTabBarInset.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: inset > 0 ? inset + 30 : 0),
      child: GlassBuilder(
        builder: (context, glass) => glass
            ? GlassButton(
                label: label,
                symbol: symbol,
                icon: Icons.edit_outlined,
                style: GlassButtonStyle.prominent,
                height: 52,
                onPressed: onPressed,
              )
            : GradientButton(label: label, icon: Icons.edit_outlined, height: 52, onPressed: onPressed),
      ),
    );
  }
}

// ------------------------------------------------------------------ 上部のバー

/// 上部バーの背景。iOS 26 の「スクロールエッジ効果」と同じく、下を流れる内容をぼかす。
class ScrollEdgeBackground extends StatelessWidget {
  const ScrollEdgeBackground({super.key, this.border = false});

  /// 下端に細い線を引く（Galaxia の固定ヘッダー）
  final bool border;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.78),
            border: border
                ? Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.6)))
                : null,
          ),
        ),
      ),
    );
  }
}

/// AppBar の代わり。リキッドグラスが使えるときは、戻る・閉じるボタンと右側のボタンを
/// ガラスにし、背景はスクロールエッジ効果にする。使えないときは今までどおりの AppBar。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
    this.bottom,
  });

  final Widget? title;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return GlassBuilder(
      builder: (context, glass) {
        if (!glass) {
          return AppBar(
            title: title,
            actions: [...actions, const SizedBox(width: 4)],
            automaticallyImplyLeading: automaticallyImplyLeading,
            bottom: bottom,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            flexibleSpace: const SizedBox.expand(child: ScrollEdgeBackground(border: true)),
          );
        }
        final route = ModalRoute.of(context);
        final canPop = automaticallyImplyLeading && (route?.canPop ?? false);
        final isDialog = route is PageRoute && route.fullscreenDialog;
        final brightness = Theme.of(context).brightness;
        return AppBar(
          title: title,
          actions: [...actions, const SizedBox(width: 8)],
          automaticallyImplyLeading: false,
          leadingWidth: canPop ? 60 : null,
          leading: canPop
              ? GlassButton(
                  symbol: isDialog ? 'xmark' : 'chevron.left',
                  icon: isDialog ? Icons.close : Icons.arrow_back,
                  tooltip: isDialog ? '閉じる' : '戻る',
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          bottom: bottom,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          // 背景が透明だと文字色の判定がずれるので、状態バーの色は明示する
          systemOverlayStyle: brightness == Brightness.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
          // AppBar は flexibleSpace に高さを指定しないので、広げないと背景が描かれない
          flexibleSpace: const SizedBox.expand(child: ScrollEdgeBackground()),
        );
      },
    );
  }
}

/// Scaffold の代わり。[scrollUnderBars] が true の画面では、リキッドグラスのときに
/// 内容が上下のバーの下まで流れる（一覧は [scrollPadding] で余白をとる）。
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.scrollUnderBars = false,
    this.aurora = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool scrollUnderBars;

  /// Galaxia のオーロラの背景を敷く
  final bool aurora;

  @override
  Widget build(BuildContext context) {
    // 上下のバーは半透明（ぼかし）なので、内容はバーの下まで流す（一覧は scrollPadding で余白をとる）
    return Scaffold(
      appBar: appBar,
      body: aurora ? AuroraBackground(child: body) : body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyBehindAppBar: scrollUnderBars,
      extendBody: scrollUnderBars,
    );
  }
}
