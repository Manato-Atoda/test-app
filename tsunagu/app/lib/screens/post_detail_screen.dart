import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/like_button.dart';
import '../widgets/mention_suggestions.dart';
import '../widgets/post_card.dart';
import '../widgets/rich_body.dart';
import 'user_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.initial, this.callbacks = const PostCallbacks()});

  final int postId;
  final Post? initial;
  final PostCallbacks callbacks;

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
  Identity _identity = Identity.real;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _comment.addListener(() => setState(() {}));
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
      widget.callbacks.onChanged?.call(detail.post);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _postChanged(Post post) {
    if (post.id == _post?.id) setState(() => _post = post);
    widget.callbacks.onChanged?.call(post);
  }

  void _postDeleted(int id) {
    widget.callbacks.onDeleted?.call(id);
    if (id == _post?.id) Navigator.of(context).pop();
  }

  PostCallbacks get _callbacks => PostCallbacks(
    onChanged: _postChanged,
    onDeleted: _postDeleted,
    onInserted: widget.callbacks.onInserted,
    onUnshared: widget.callbacks.onUnshared,
  );

  void _addComment(Comment c) {
    setState(() => _comments = [..._comments, c]);
    final p = _post;
    if (p != null) _postChanged(p.withCommentCount(p.commentCount + 1));
  }

  Future<void> _send({int? quickIndex}) async {
    final text = _comment.text.trim();
    if ((quickIndex == null && text.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final c = await AppScope.read(context).api.addComment(
        widget.postId,
        body: quickIndex == null ? text : null,
        identity: _identity,
        quickIndex: quickIndex,
      );
      if (!mounted) return;
      if (quickIndex == null) _comment.clear();
      _addComment(c);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replaceComment(Comment c) {
    setState(() => _comments = [for (final x in _comments) x.id == c.id ? c : x]);
  }

  Future<void> _toggleCommentLike(Comment c) async {
    final api = AppScope.read(context).api;
    try {
      _replaceComment(await api.setCommentLike(c.id, !c.likedByMe));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editComment(Comment c) async {
    final body = await textInputDialog(
      context,
      title: 'コメントを編集',
      initialValue: c.body,
      maxLength: _maxComment,
      maxLines: 6,
    );
    if (body == null || body == c.body || !mounted) return;
    try {
      _replaceComment(await AppScope.read(context).api.editComment(c.id, body));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteComment(Comment c) async {
    final ok = await confirmDialog(
      context,
      title: 'このコメントを削除しますか?',
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
    final p = context.m;
    final state = AppScope.of(context);

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
              child: PostCard(post: post, inDetail: true, callbacks: _callbacks),
            ),
            const SizedBox(height: 18),
            ContentWidth(
              child: Text(
                'コメント（${_comments.length}）',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading && _comments.isEmpty)
              const LoadingFooter()
            else if (_comments.isEmpty)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('まだコメントがありません', style: TextStyle(color: p.muted)),
                ),
              ),
            for (final c in _comments)
              ContentWidth(
                child: _CommentTile(
                  comment: c,
                  onLike: () => _toggleCommentLike(c),
                  onEdit: () => _editComment(c),
                  onDelete: () => _deleteComment(c),
                  onReport: () => _reportComment(c),
                ),
              ),
          ],
        ),
      );
    }

    final features = state.company?.features ?? const CompanyFeatures();
    final canSwitchIdentity = features.identityDepartment || features.identityAnonymous;
    final quick = state.company?.quickComments ?? QuickComment.defaults;

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(post == null ? '投稿' : (post.isCommit ? 'COMMIT' : (post.channel?.label ?? '投稿'))),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            if (post != null)
              Material(
                color: p.surfaceElevated,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: quick.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 6),
                              itemBuilder: (context, i) => ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: Text('${quick[i].emoji} ${quick[i].text}', style: const TextStyle(fontSize: 12)),
                                onPressed: _sending ? null : () => _send(quickIndex: i),
                              ),
                            ),
                          ),
                          MentionSuggestions(controller: _comment),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (canSwitchIdentity)
                                _IdentityPicker(value: _identity, onChanged: (v) => setState(() => _identity = v)),
                              Expanded(
                                child: TextField(
                                  controller: _comment,
                                  enabled: !_sending,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: _maxComment,
                                  decoration: const InputDecoration(
                                    hintText: 'コメントを書く... (@ でメンション)',
                                    counterText: '',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filled(
                                tooltip: '送信',
                                style: IconButton.styleFrom(backgroundColor: p.accent),
                                onPressed: _comment.text.trim().isEmpty || _sending ? null : _send,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
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

/// コメント欄の発信者切り替え（小さなボタン）。
class _IdentityPicker extends StatelessWidget {
  const _IdentityPicker({required this.value, required this.onChanged});

  final Identity value;
  final ValueChanged<Identity> onChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    return PopupMenuButton<Identity>(
      tooltip: '発信者',
      initialValue: value,
      onSelected: (v) {
        final reason = state.identityUnavailableReason(v);
        if (reason != null) {
          showInfo(context, reason);
          return;
        }
        onChanged(v);
      },
      itemBuilder: (_) => [
        for (final id in Identity.values)
          PopupMenuItem(
            value: id,
            enabled: true,
            child: Text(
              '${id.label}（${state.identityUnavailableReason(id) == null ? state.identityPreview(id) : '未設定'}）',
              style: TextStyle(color: state.identityUnavailableReason(id) == null ? null : p.muted),
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 6, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(999)),
        child: Text(
          value.label,
          style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.comment,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final Comment comment;
  final VoidCallback onLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final p = context.m;
    final items = <PopupMenuEntry<String>>[
      if (c.canEdit && !c.hidden && !c.isQuick) const PopupMenuItem(value: 'edit', child: Text('編集')),
      if (c.canDelete) const PopupMenuItem(value: 'delete', child: Text('削除')),
      if (!c.isMine && !c.hidden) const PopupMenuItem(value: 'report', child: Text('管理者に通報')),
    ];
    final long = c.body.length > 160 || '\n'.allMatches(c.body).length > 4;
    final tag = identityTag(context, c.identity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: c.identity == Identity.real && c.author != null
                ? () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: c.author!.id)))
                : null,
            child: AuthorAvatar(item: c, size: 32),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
              decoration: BoxDecoration(
                color: p.surfaceElevated,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.author != null && c.identity == Identity.real
                              ? displayNameWithStatus(c.author!)
                              : c.shownName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                      if (tag != null) ...[const SizedBox(width: 6), tag],
                      const SizedBox(width: 6),
                      Text(relativeTime(c.createdAt), style: TextStyle(color: p.muted, fontSize: 11.5)),
                      if (c.editedAt != null) Text(' · 編集済み', style: TextStyle(color: p.muted, fontSize: 11.5)),
                      const Spacer(),
                      if (items.isNotEmpty)
                        SizedBox(
                          width: 28,
                          height: 24,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            tooltip: 'コメントを編集・削除',
                            iconSize: 16,
                            icon: Icon(Icons.more_horiz, color: p.muted),
                            itemBuilder: (_) => items,
                            onSelected: (v) {
                              switch (v) {
                                case 'edit':
                                  widget.onEdit();
                                case 'delete':
                                  widget.onDelete();
                                case 'report':
                                  widget.onReport();
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (c.hidden)
                    Text(
                      'このコメントは管理者により非表示になりました。',
                      style: TextStyle(color: p.muted, fontStyle: FontStyle.italic, fontSize: 13.5),
                    )
                  else if (c.isQuick)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        c.body,
                        style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    )
                  else ...[
                    RichBody(
                      c.body,
                      maxLines: long && !_expanded ? 4 : null,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (long)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _expanded ? '折りたたむ' : '続きを読む',
                            style: TextStyle(color: p.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                  if (!c.hidden)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: LikeButton(liked: c.likedByMe, count: c.likeCount, onToggle: widget.onLike, compact: true),
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
