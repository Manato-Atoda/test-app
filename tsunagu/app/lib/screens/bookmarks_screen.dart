import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/feed_view.dart';
import '../widgets/glass.dart';
import '../widgets/post_card.dart';

/// 保存した投稿（投稿 / COMMIT を切り替え）。
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  String _kind = 'post';
  late FeedController _feed = _make();

  FeedController _make() {
    final api = AppScope.read(context).api;
    final kind = _kind;
    return FeedController(
      fetch: (before) => api.bookmarks(kind: kind, before: before),
    );
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  void _switch(String kind) {
    if (kind == _kind) return;
    final old = _feed;
    setState(() {
      _kind = kind;
      _feed = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// 保存を外したら一覧から消す。
  void _changed(Post post) {
    if (!post.bookmarkedByMe) {
      _feed.remove(post.id);
    } else {
      _feed.replace(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: const GlassAppBar(title: Text('ブックマーク')),
      body: FeedView(
        key: ValueKey(_kind),
        controller: _feed,
        callbacks: PostCallbacks(onChanged: _changed, onDeleted: _feed.remove, onUnshared: _feed.removeMyShareOf),
        emptyMessage: _kind == 'post' ? '保存した投稿はありません' : '保存した COMMIT はありません',
        emptyIcon: Icons.bookmark_border_rounded,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'post', label: Text('投稿'), icon: Icon(Icons.forum_outlined)),
              ButtonSegment(value: 'commit', label: Text('COMMIT'), icon: Icon(Icons.flag_outlined)),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _switch(s.first),
          ),
        ),
      ),
    );
  }
}
