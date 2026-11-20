import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import 'common.dart';
import 'glass.dart';
import 'post_card.dart';

typedef PageFetcher = Future<FeedPage> Function(int? before);

/// 投稿一覧の読み込み状態（無限スクロール・引っ張って更新・新着の確認）。
class FeedController extends ChangeNotifier {
  FeedController({required this.fetch, this.accepts, this.fetchNewer});

  /// タイムライン（ホーム・チャンネル・お知らせ）。
  factory FeedController.timeline(ApiClient api, {int? channelId, String? kind}) => FeedController(
    fetch: (before) => api.feed(channelId: channelId, kind: kind, before: before),
    fetchNewer: channelId == null && kind == null ? (after) => api.feed(after: after, limit: 50) : null,
    accepts: (p) {
      if (p.isCommit || p.quoteOf?.isCommit == true) return false;
      if (channelId != null && p.channel?.id != channelId) return false;
      if (kind != null && p.kind != kind) return false;
      return true;
    },
  );

  final PageFetcher fetch;

  /// 新しく作った投稿をこの一覧に入れてよいか。
  final bool Function(Post post)? accepts;

  /// after より新しい投稿（「新しい投稿があります」の確認用）。
  final Future<FeedPage> Function(int after)? fetchNewer;

  final List<Post> posts = [];
  int? _nextBefore;
  bool _hasMore = true;
  bool loading = false;
  bool loaded = false;
  Object? error;

  /// まだ表示していない新しい投稿の数。
  int newCount = 0;

  bool get hasMore => _hasMore;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await fetch(null);
      posts
        ..clear()
        ..addAll(page.posts);
      _nextBefore = page.nextBefore;
      _hasMore = page.nextBefore != null;
      loaded = true;
      newCount = 0;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || !_hasMore || _nextBefore == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await fetch(_nextBefore);
      final known = posts.map((p) => p.id).toSet();
      posts.addAll(page.posts.where((p) => !known.contains(p.id)));
      _nextBefore = page.nextBefore;
      _hasMore = page.nextBefore != null;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 新しい投稿があるか確かめる（数だけ数え、一覧はまだ変えない）。
  Future<void> checkNewer() async {
    final f = fetchNewer;
    if (f == null || !loaded || loading || posts.isEmpty) return;
    try {
      final page = await f(posts.first.id);
      final known = posts.map((p) => p.id).toSet();
      final count = page.posts.where((p) => !known.contains(p.id) && !p.isMine).length;
      if (count != newCount) {
        newCount = count;
        notifyListeners();
      }
    } catch (_) {
      // 確認の失敗は表示しない。
    }
  }

  /// 投稿の変更を反映する（シェアの中に入っている元の投稿も）。
  void replace(Post post) {
    var changed = false;
    for (var i = 0; i < posts.length; i++) {
      final p = posts[i];
      if (p.id == post.id) {
        posts[i] = post;
        changed = true;
      } else if (p.quoteOf?.id == post.id) {
        posts[i] = p.copyWith(quoteOf: post);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void remove(int postId) {
    posts.removeWhere((p) => p.id == postId || (p.isShare && p.quoteOf?.id == postId));
    notifyListeners();
  }

  /// 自分のシェアを取り消したとき、その「シェア」を一覧から消す。
  void removeMyShareOf(int originalId) {
    posts.removeWhere((p) => p.isShare && p.isMine && p.quoteOf?.id == originalId);
    notifyListeners();
  }

  /// 新しく投稿したものを先頭に入れる（この一覧の条件に合う場合）。
  void insertNew(Post post) {
    if (accepts != null && !accepts!(post)) return;
    if (posts.any((p) => p.id == post.id)) return;
    posts.insert(0, post);
    loaded = true;
    notifyListeners();
  }

  PostCallbacks get callbacks =>
      PostCallbacks(onChanged: replace, onDeleted: remove, onInserted: insertNew, onUnshared: removeMyShareOf);
}

class FeedView extends StatefulWidget {
  const FeedView({
    super.key,
    required this.controller,
    this.showChannel = true,
    this.header,
    this.emptyMessage = 'タイムラインはまだ静かです',
    this.emptyIcon = Icons.forum_outlined,
    this.callbacks,
  });

  final FeedController controller;
  final bool showChannel;
  final Widget? header;
  final String emptyMessage;
  final IconData emptyIcon;

  /// 一覧の外にも伝えたいとき（ホームと COMMIT など）。省略するとこの一覧だけを更新する。
  final PostCallbacks? callbacks;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (!widget.controller.loaded && !widget.controller.loading) {
      widget.controller.refresh();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) widget.controller.loadMore();
  }

  Future<void> _showNew() async {
    await widget.controller.refresh();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.read(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final callbacks = widget.callbacks ?? c.callbacks;
        if (!c.loaded) {
          if (c.error != null) {
            return MessageView(
              icon: Icons.cloud_off_outlined,
              message: c.error is ApiException ? (c.error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: c.refresh,
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final itemCount = c.posts.length + (widget.header != null ? 1 : 0) + 1;
        final list = RefreshIndicator(
          onRefresh: c.refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollPadding(context, const EdgeInsets.fromLTRB(12, 8, 12, 110)),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              var i = index;
              if (widget.header != null) {
                if (i == 0) return ContentWidth(child: widget.header!);
                i -= 1;
              }
              if (i < c.posts.length) {
                final post = c.posts[i];
                // 画面に出た投稿を「見た」として記録する（シェアなら元の投稿）
                state.trackView(post.quoteOf != null && post.isShare ? post.quoteOf!.id : post.id);
                return ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PostCard(
                      key: ValueKey('${post.id}-${post.kind}'),
                      post: post,
                      showChannel: widget.showChannel,
                      callbacks: callbacks,
                    ),
                  ),
                );
              }
              if (c.posts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: MessageView(icon: widget.emptyIcon, message: widget.emptyMessage),
                );
              }
              if (c.hasMore) {
                if (c.error != null) {
                  return Center(
                    child: TextButton(onPressed: c.loadMore, child: const Text('続きを読み込む')),
                  );
                }
                // 1 ページ目が画面に収まった場合もスクロールを待たずに続きを読む。
                WidgetsBinding.instance.addPostFrameCallback((_) => c.loadMore());
                return const LoadingFooter();
              }
              return const SizedBox(height: 24);
            },
          ),
        );
        if (c.newCount <= 0) return list;
        return Stack(
          children: [
            list,
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: NewPostsPill(count: c.newCount, onTap: _showNew),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 「n 件の新しい投稿」のピル。
class NewPostsPill extends StatelessWidget {
  const NewPostsPill({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: buttonGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x406366F1), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '$count 件の新しい投稿',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
