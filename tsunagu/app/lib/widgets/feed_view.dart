import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'common.dart';
import 'post_card.dart';

/// タイムラインの読み込み状態（無限スクロール・引っ張って更新）。
class FeedController extends ChangeNotifier {
  FeedController({required this.api, this.channelId, this.kind});

  final ApiClient api;
  final int? channelId;
  final String? kind;

  final List<Post> posts = [];
  int? _nextBefore;
  bool _hasMore = true;
  bool loading = false;
  bool loaded = false;
  Object? error;

  bool get hasMore => _hasMore;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.feed(channelId: channelId, kind: kind);
      posts
        ..clear()
        ..addAll(page.posts);
      _nextBefore = page.nextBefore;
      _hasMore = page.nextBefore != null;
      loaded = true;
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
      final page = await api.feed(channelId: channelId, kind: kind, before: _nextBefore);
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

  void replace(Post post) {
    final i = posts.indexWhere((p) => p.id == post.id);
    if (i >= 0) {
      posts[i] = post;
      notifyListeners();
    }
  }

  void remove(int postId) {
    posts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }

  /// 新しく投稿したものを先頭に入れる（このタイムラインの条件に合う場合）。
  void insertNew(Post post) {
    if (channelId != null && post.channel.id != channelId) return;
    if (kind != null && post.kind != kind) return;
    posts.insert(0, post);
    notifyListeners();
  }
}

class FeedView extends StatefulWidget {
  const FeedView({
    super.key,
    required this.controller,
    this.showChannel = true,
    this.header,
    this.emptyMessage = 'まだ投稿はありません。',
  });

  final FeedController controller;
  final bool showChannel;
  final Widget? header;
  final String emptyMessage;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
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
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              var i = index;
              if (widget.header != null) {
                if (i == 0) return ContentWidth(child: widget.header!);
                i -= 1;
              }
              if (i < c.posts.length) {
                final post = c.posts[i];
                return ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PostCard(
                      key: ValueKey(post.id),
                      post: post,
                      showChannel: widget.showChannel,
                      onChanged: c.replace,
                      onDeleted: c.remove,
                    ),
                  ),
                );
              }
              if (c.posts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: MessageView(icon: Icons.forum_outlined, message: widget.emptyMessage),
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
      },
    );
  }
}
