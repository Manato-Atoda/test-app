import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import '../widgets/rich_body.dart';
import 'user_profile_screen.dart';
import '../widgets/glass.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    this.initial,
    this.onChanged,
    this.onDeleted,
  });

  final int postId;
  final Post? initial;
  final PostChanged? onChanged;
  final PostDeleted? onDeleted;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  static const _maxComment = 2000;

  Post? _post;
  List<Comment> _comments = const [];
  bool _loading = true;
  Object? _error;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await AppScope.read(context).api.post(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = detail.post;
        _comments = detail.comments;
      });
      widget.onChanged?.call(detail.post);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _postChanged(Post post) {
    setState(() => _post = post);
    widget.onChanged?.call(post);
  }

  void _postDeleted(int id) {
    widget.onDeleted?.call(id);
    Navigator.of(context).pop();
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await AppScope.read(context).api.addComment(widget.postId, text);
      if (!mounted) return;
      _comment.clear();
      setState(() => _comments = [..._comments, c]);
      final p = _post;
      if (p != null) {
        _postChanged(p.withCommentCount(p.commentCount + 1));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(Comment c) async {
    final ok = await confirmDialog(
      context,
      title: 'コメントを削除しますか？',
      message: '削除したコメントは表示されなくなります。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.deleteComment(c.id);
      if (!mounted) return;
      setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
      final p = _post;
      if (p != null) _postChanged(p.withCommentCount(p.commentCount - 1));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reportComment(Comment c) async {
    final reason = await textInputDialog(
      context,
      title: 'コメントを管理者に通報',
      hint: '理由',
      confirmLabel: '通報する',
      maxLength: 500,
      maxLines: 4,
    );
    if (reason == null || !mounted) return;
    try {
      await AppScope.read(context).api.report(targetType: 'comment', targetId: c.id, reason: reason);
      if (mounted) showInfo(context, '管理者に通報しました。');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final theme = Theme.of(context);
    final me = AppScope.of(context).me;

    Widget body;
    if (post == null) {
      body = _error != null
          ? MessageView(
              icon: Icons.error_outline,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: _load,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            ContentWidth(
              child: PostCard(
                post: post,
                inDetail: true,
                onChanged: _postChanged,
                onDeleted: _postDeleted,
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Text(
                'コメント（${_comments.length}）',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading && _comments.isEmpty)
              const LoadingFooter()
            else if (_comments.isEmpty)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('まだコメントはありません。', style: theme.textTheme.bodyMedium),
                ),
              ),
            for (final c in _comments)
              ContentWidth(
                child: _CommentTile(
                  comment: c,
                  isMine: c.author.id == me?.id,
                  onDelete: () => _deleteComment(c),
                  onReport: () => _reportComment(c),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: GlassAppBar(title: Text(post == null ? '投稿' : '#${post.channel.name}')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            if (post != null)
              Material(
                elevation: 3,
                color: theme.colorScheme.surfaceContainer,
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: _maxComment,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'コメントを書く',
                              counterText: '',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filled(
                          tooltip: '送信',
                          onPressed: _comment.text.trim().isEmpty || _sending ? null : _send,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isMine,
    required this.onDelete,
    required this.onReport,
  });

  final Comment comment;
  final bool isMine;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = <PopupMenuEntry<String>>[
      if (comment.canDelete) const PopupMenuItem(value: 'delete', child: Text('削除')),
      if (!isMine && !comment.hidden) const PopupMenuItem(value: 'report', child: Text('管理者に通報')),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: comment.author.id)),
            ),
            child: UserAvatar(user: comment.author, size: 32),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: displayNameWithStatus(comment.author),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: '  ${relativeTime(comment.createdAt)}',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (comment.hidden)
                          Text(
                            'このコメントは管理者により非表示になりました。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          RichBody(comment.body, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  if (items.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'メニュー',
                      iconSize: 18,
                      icon: const Icon(Icons.more_vert),
                      itemBuilder: (_) => items,
                      onSelected: (v) => v == 'delete' ? onDelete() : onReport(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
