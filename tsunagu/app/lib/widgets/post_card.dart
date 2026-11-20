import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../screens/acks_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../state/app_scope.dart';
import '../utils/format.dart';
import 'common.dart';
import 'rich_body.dart';

typedef PostChanged = void Function(Post post);
typedef PostDeleted = void Function(int postId);

/// タイムラインの投稿 1 件。
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onDeleted,
    this.showChannel = true,
    this.inDetail = false,
  });

  final Post post;
  final PostChanged? onChanged;
  final PostDeleted? onDeleted;
  final bool showChannel;

  /// 投稿詳細画面の中で表示しているとき（タップで詳細を開かない）。
  final bool inDetail;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _busy = false;

  Post get post => widget.post;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDetail() {
    if (widget.inDetail) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(
          postId: post.id,
          initial: post,
          onChanged: widget.onChanged,
          onDeleted: widget.onDeleted,
        ),
      ),
    );
  }

  void _openAuthor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: post.author.id)),
    );
  }

  Future<void> _toggleReaction(String key) => _run(() async {
    final api = AppScope.read(context).api;
    final mine = post.reaction(key)?.reactedByMe ?? false;
    final updated = await api.setReaction(post.id, key, !mine);
    widget.onChanged?.call(updated);
  });

  Future<void> _pickReaction() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final e in Reaction.emojis.entries)
                ActionChip(
                  avatar: Text(e.value, style: const TextStyle(fontSize: 18)),
                  label: Text(Reaction.labels[e.key] ?? e.key),
                  onPressed: () => Navigator.pop(context, e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (key != null) await _toggleReaction(key);
  }

  Future<void> _ack() => _run(() async {
    final updated = await AppScope.read(context).api.acknowledge(post.id);
    widget.onChanged?.call(updated);
  });

  Future<void> _edit() async {
    final body = await textInputDialog(
      context,
      title: '投稿を編集',
      initialValue: post.body,
      maxLength: 4000,
      maxLines: 10,
    );
    if (body == null || body == post.body || !mounted) return;
    await _run(() async {
      final updated = await AppScope.read(context).api.editPost(post.id, body);
      widget.onChanged?.call(updated);
    });
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: '投稿を削除しますか？',
      message: '削除した投稿は表示されなくなります（記録は会社の規定に従って保管されます）。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await AppScope.read(context).api.deletePost(post.id);
      widget.onDeleted?.call(post.id);
      if (mounted) showInfo(context, '投稿を削除しました。');
    });
  }

  Future<void> _report() async {
    final reason = await textInputDialog(
      context,
      title: '投稿を管理者に通報',
      hint: '理由（例: 個人情報が含まれている、ハラスメントにあたる など）',
      confirmLabel: '通報する',
      maxLength: 500,
      maxLines: 4,
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      await AppScope.read(context).api.report(targetType: 'post', targetId: post.id, reason: reason);
      if (mounted) showInfo(context, '管理者に通報しました。ご協力ありがとうございます。');
    });
  }

  void _showAcks() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AcksScreen(postId: post.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isMine = state.me?.id == post.author.id;
    final canSeeAcks = post.requireAck && (isMine || state.isAdmin);

    final meta = [
      if (post.author.affiliation.isNotEmpty) post.author.affiliation,
      if (widget.showChannel) '#${post.channel.name}',
      relativeTime(post.createdAt),
    ].join(' · ');

    final menuItems = <PopupMenuEntry<String>>[
      if (post.canEdit) const PopupMenuItem(value: 'edit', child: Text('編集')),
      if (post.canDelete) const PopupMenuItem(value: 'delete', child: Text('削除')),
      if (canSeeAcks) const PopupMenuItem(value: 'acks', child: Text('確認状況を見る')),
      if (!isMine) const PopupMenuItem(value: 'report', child: Text('管理者に通報')),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: post.isAnnouncement
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 1.2),
            )
          : null,
      child: InkWell(
        onTap: widget.inDetail ? null : _openDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _openAuthor,
                    child: UserAvatar(user: post.author),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayNameWithStatus(post.author),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (menuItems.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'メニュー',
                      icon: const Icon(Icons.more_horiz),
                      itemBuilder: (_) => menuItems,
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            _edit();
                          case 'delete':
                            _delete();
                          case 'acks':
                            _showAcks();
                          case 'report':
                            _report();
                        }
                      },
                    ),
                ],
              ),
              if (post.isAnnouncement) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.campaign_outlined, size: 18, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'お知らせ',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 4),
                child: RichBody(post.body),
              ),
              if (post.editedAt != null)
                Text(
                  '（編集済み）',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              if (post.requireAck)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Row(
                    children: [
                      if (post.ackedByMe)
                        Chip(
                          avatar: Icon(Icons.check_circle, color: scheme.primary, size: 18),
                          label: const Text('確認済み'),
                          visualDensity: VisualDensity.compact,
                        )
                      else
                        FilledButton.icon(
                          onPressed: _busy ? null : _ack,
                          icon: const Icon(Icons.check),
                          label: const Text('確認しました'),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: canSeeAcks ? _showAcks : null,
                          child: Text(
                            '確認 ${post.ackCount}人',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final r in post.reactions.where((r) => r.count > 0))
                    FilterChip(
                      selected: r.reactedByMe,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      tooltip: Reaction.labels[r.key],
                      label: Text('${r.emoji} ${r.count}'),
                      onSelected: _busy ? null : (_) => _toggleReaction(r.key),
                    ),
                  IconButton(
                    tooltip: 'リアクション',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : _pickReaction,
                    icon: const Icon(Icons.add_reaction_outlined, size: 20),
                  ),
                  TextButton.icon(
                    onPressed: widget.inDetail ? null : _openDetail,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(post.commentCount > 0 ? 'コメント ${post.commentCount}' : 'コメント'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
