import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/vamos_theme.dart';
import 'adaptive.dart';

/// 広い画面（開いた iPhone Duo など）では左に一覧・右に記事を並べ、
/// 縦長の画面では一覧だけを表示して、記事は新しいページで開く。
///
/// 端末を閉じて画面が狭くなると、右に表示していた記事をそのまま 1 画面の記事ページにする。
/// もう一度開くと、記事ページは閉じて右側に戻る。どちらも読んでいた位置を保つ。
class ListDetail<T> extends StatefulWidget {
  const ListDetail({
    super.key,
    required this.items,
    required this.idOf,
    required this.routeNameOf,
    required this.listBuilder,
    required this.detailBuilder,
    this.active = true,
  });

  /// 一覧の項目（右側で何も選んでいないときは先頭を表示する）
  final List<T> items;

  /// 項目を見分ける ID
  final String Function(T item) idOf;

  /// 記事ページとして開くときのルート名（例：/interviews/<slug>）
  final String Function(T item) routeNameOf;

  /// 一覧。[selectedId] は右側に表示中の項目（1 画面のときは null）、[open] で項目を開く
  final Widget Function(BuildContext context, String? selectedId, ValueChanged<T> open) listBuilder;

  /// 記事
  final Widget Function(BuildContext context, T item, PaneDetailOptions options) detailBuilder;

  /// この画面がいま表示されているか（下のタブで隠れているときは false）
  final bool active;

  @override
  State<ListDetail<T>> createState() => _ListDetailState<T>();
}

/// 記事を右側に置くか、ページとして開くかの指定
class PaneDetailOptions {
  const PaneDetailOptions({required this.embedded, this.scrollController, this.initialOffset = 0});

  /// 一覧の右側に置く（戻るボタンやロゴを出さない）
  final bool embedded;

  /// 右側に置くときのスクロール（一覧側で位置を読むため）
  final ScrollController? scrollController;

  /// 表示したら移動するスクロール位置（前に読んでいた位置）
  final double initialOffset;
}

class _ListDetailState<T> extends State<ListDetail<T>> {
  /// 一覧の位置を、1 画面と 2 画面を行き来しても保つ
  final _listKey = GlobalKey();

  /// 自分で選んだ項目（null のときは先頭を表示する）
  T? _selected;
  ScrollController _paneController = ScrollController();
  double _paneOffset = 0;

  /// 右側の記事を作り直すための番号（同じ記事を選び直したときも先頭から表示する）
  int _generation = 0;
  bool? _wasTwoPane;
  bool _routeOpen = false;

  @override
  void dispose() {
    _paneController.dispose();
    super.dispose();
  }

  T? get _shown {
    final selected = _selected;
    if (selected != null && widget.items.any((item) => widget.idOf(item) == widget.idOf(selected))) return selected;
    return widget.items.isEmpty ? null : widget.items.first;
  }

  void _select(T item, {double offset = 0}) {
    final previous = _paneController;
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    setState(() {
      _selected = item;
      _paneController = ScrollController();
      _paneOffset = offset;
      _generation++;
    });
  }

  void _open(T item) {
    if (Adaptive.useTwoPane(context)) {
      _select(item);
    } else {
      _push(item, offset: 0, instant: false);
    }
  }

  Future<void> _push(T item, {required double offset, required bool instant}) async {
    _routeOpen = true;
    final result = await Navigator.of(context).push(PaneDetailRoute(
      instant: instant,
      settings: RouteSettings(name: widget.routeNameOf(item)),
      builder: (context) => widget.detailBuilder(
        context,
        item,
        PaneDetailOptions(embedded: false, initialOffset: offset),
      ),
    ));
    _routeOpen = false;
    // 画面が広くなって記事ページが閉じた → 右側に、読んでいた位置で表示する
    if (mounted && result != null) _select(item, offset: result.offset);
  }

  /// 2 画面 → 1 画面になったとき、右の記事を読んでいたら記事ページにする
  void _collapse() {
    final item = _shown;
    final offset = _paneController.hasClients ? _paneController.offset : _paneOffset;
    final reading = _selected != null || offset > 0;
    final onScreen = widget.active && (ModalRoute.of(context)?.isCurrent ?? true);
    if (item == null || !reading || !onScreen || _routeOpen) return;
    _paneOffset = offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _push(item, offset: offset, instant: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final twoPane = Adaptive.useTwoPane(context);
    if (_wasTwoPane == true && !twoPane) _collapse();
    _wasTwoPane = twoPane;

    final item = twoPane ? _shown : null;
    final list = KeyedSubtree(
      key: _listKey,
      child: widget.listBuilder(context, item == null ? null : widget.idOf(item), _open),
    );
    if (!twoPane) return list;
    return TwoPane(
      start: list,
      end: item == null
          ? const _EmptyDetail()
          : KeyedSubtree(
              key: ValueKey('${widget.idOf(item)}#$_generation'),
              child: widget.detailBuilder(
                context,
                item,
                PaneDetailOptions(embedded: true, scrollController: _paneController, initialOffset: _paneOffset),
              ),
            ),
    );
  }
}

/// 画面を真ん中（iPhone Duo の折り目）で左右に分ける。
/// それぞれの側には、その側の幅と、その側にかかるセーフエリアだけを伝える。
class TwoPane extends StatelessWidget {
  const TwoPane({super.key, required this.start, required this.end});

  final Widget start;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final split = (size.width / 2).roundToDouble();
    final endWidth = size.width - split - 1;
    return Row(
      children: [
        SizedBox(
          width: split,
          child: MediaQuery(
            data: media.copyWith(
              size: Size(split, size.height),
              padding: media.padding.copyWith(right: 0),
              viewPadding: media.viewPadding.copyWith(right: 0),
            ),
            child: start,
          ),
        ),
        const ColoredBox(color: VamosColors.border, child: SizedBox(width: 1, height: double.infinity)),
        SizedBox(
          width: endWidth,
          child: MediaQuery(
            data: media.copyWith(
              size: Size(endWidth, size.height),
              padding: media.padding.copyWith(left: 0),
              viewPadding: media.viewPadding.copyWith(left: 0),
            ),
            child: end,
          ),
        ),
      ],
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: VamosColors.surface,
      child: Center(
        child: Text('記事を選ぶと、ここに表示されます', style: TextStyle(color: VamosColors.textMuted)),
      ),
    );
  }
}

/// [ListDetail] から開いた記事ページ。画面が広くなると自分で閉じ、読んでいた位置を一覧に返す。
class PaneDetailRoute extends MaterialPageRoute<PaneReturn> {
  PaneDetailRoute({required super.builder, super.settings, this.instant = false});

  /// 開くときにアニメーションしない（端末を閉じたとき、右の記事がそのまま全画面になるように）
  final bool instant;

  bool _closeInstantly = false;

  @override
  Duration get transitionDuration => instant ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _closeInstantly ? Duration.zero : super.reverseTransitionDuration;

  /// 画面が広くなったので、記事ページを閉じて一覧の右側に戻す
  void returnToPane(double offset) {
    if (!isCurrent) return;
    _closeInstantly = true;
    navigator?.pop(PaneReturn(offset));
  }
}

/// 記事ページから一覧に返す、読んでいた位置
class PaneReturn {
  const PaneReturn(this.offset);

  final double offset;
}

/// 記事画面で、2 画面表示との行き来に使う処理
mixin PaneDetailMixin<W extends StatefulWidget> on State<W> {
  /// 一覧から渡された指定
  PaneDetailOptions get paneOptions;

  /// 本文のスクロール（右側に置くときは一覧から渡されたもの）
  late final ScrollController scrollController = paneOptions.scrollController ?? ScrollController();

  late double? _pendingOffset = paneOptions.initialOffset > 0 ? paneOptions.initialOffset : null;
  bool _returning = false;

  /// 本文を表示できたら、前に読んでいた位置まで移動する
  void restoreScrollOffset() {
    final offset = _pendingOffset;
    if (offset == null) return;
    _pendingOffset = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.jumpTo(math.min(offset, scrollController.position.maxScrollExtent));
    });
  }

  /// 記事ページとして開いているときに画面が広くなったら、一覧の右側に戻す
  void returnToPaneIfWide() {
    final route = ModalRoute.of(context);
    if (_returning || route is! PaneDetailRoute || !Adaptive.useTwoPane(context)) return;
    _returning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) route.returnToPane(scrollController.hasClients ? scrollController.offset : 0);
    });
  }

  @override
  void dispose() {
    if (paneOptions.scrollController == null) scrollController.dispose();
    super.dispose();
  }
}
