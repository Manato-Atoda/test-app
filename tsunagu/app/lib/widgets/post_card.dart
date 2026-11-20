import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../screens/acks_screen.dart';
import '../screens/compose_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'brand.dart';
import 'common.dart';
import 'image_grid.dart';
import 'like_button.dart';
import 'rich_body.dart';

typedef PostChanged = void Function(Post post);
typedef PostDeleted = void Function(int postId);

/// 投稿まわりの変更を一覧に伝えるためのコールバック一式。
class PostCallbacks {
  const PostCallbacks({this.onChanged, this.onDeleted, this.onInserted, this.onUnshared});

  /// 投稿（シェアなら元の投稿）が変わった。
  final PostChanged? onChanged;
  final PostDeleted? onDeleted;

  /// シェア・引用で新しい投稿ができた。
  final PostChanged? onInserted;

  /// 自分のシェアを取り消した（元の投稿の id）。
  final PostDeleted? onUnshared;
}

/// タイムラインの投稿 1 件（Galaxia のカード）。
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.callbacks = const PostCallbacks(),
    this.showChannel = true,
    this.inDetail = false,
  });

  final Post post;
  final PostCallbacks callbacks;
  final bool showChannel;

  /// 投稿詳細画面の中で表示しているとき（タップで詳細を開かない）。
  final bool inDetail;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _busy = false;

  /// 操作の対象（シェアなら元の投稿）。
  Post? get _target => widget.post.isShare ? widget.post.quoteOf : widget.post;

  PostCallbacks get _cb => widget.callbacks;

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

  void _openDetail(Post t) {
    if (widget.inDetail && !widget.post.isShare) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(postId: t.id, initial: t, callbacks: _cb),
      ),
    );
  }

  void _openAuthor(Post t) {
    final a = t.author;
    if (a == null || t.identity != Identity.real) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: a.id)));
  }

  Future<void> _toggleLike(Post t) async {
    final api = AppScope.read(context).api;
    final next = !t.likedByMe;
    _cb.onChanged?.call(t.copyWith(likedByMe: next, likeCount: t.likeCount + (next ? 1 : -1)));
    try {
      _cb.onChanged?.call(await api.setLike(t.id, next));
    } catch (e) {
      _cb.onChanged?.call(t);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleBookmark(Post t) async {
    final api = AppScope.read(context).api;
    final next = !t.bookmarkedByMe;
    _cb.onChanged?.call(t.copyWith(bookmarkedByMe: next));
    try {
      _cb.onChanged?.call(await api.setBookmark(t.id, next));
      if (mounted) showInfo(context, next ? '保存しました（メニューの「ブックマーク」から見られます）' : '保存を外しました');
    } catch (e) {
      _cb.onChanged?.call(t);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _shareMenu(Post t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: const Text('そのままシェア'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.format_quote_rounded),
              title: const Text('引用してコメント'),
              subtitle: const Text('この投稿について何を伝えたい?'),
              onTap: () => Navigator.pop(context, 'quote'),
            ),
            if (t.sharedByMe)
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('シェアを取り消す'),
                onTap: () => Navigator.pop(context, 'unshare'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'share':
        await _run(() async {
          final share = await AppScope.read(context).api.share(t.id);
          _cb.onInserted?.call(share);
          _cb.onChanged?.call(share.quoteOf ?? t.copyWith(sharedByMe: true, shareCount: t.shareCount + 1));
          if (mounted) showInfo(context, 'シェアしました');
        });
      case 'quote':
        final quote = await Navigator.of(context)
            .push<Post>(MaterialPageRoute(builder: (_) => ComposeScreen.quote(quoteOf: t), fullscreenDialog: true));
        if (quote != null) {
          _cb.onInserted?.call(quote);
          _cb.onChanged?.call(quote.quoteOf ?? t.copyWith(shareCount: t.shareCount + 1));
          if (mounted) showInfo(context, '引用しました');
        }
      case 'unshare':
        await _run(() async {
          final original = await AppScope.read(context).api.unshare(t.id);
          _cb.onChanged?.call(original);
          _cb.onUnshared?.call(t.id);
          if (mounted) showInfo(context, 'シェアを取り消しました');
        });
    }
  }

  Future<void> _ack(Post t) => _run(() async {
    _cb.onChanged?.call(await AppScope.read(context).api.acknowledge(t.id));
  });

  Future<void> _edit(Post t) async {
    final body = await textInputDialog(context, title: '投稿を編集', initialValue: t.body, maxLength: 4000, maxLines: 10);
    if (body == null || body == t.body || !mounted) return;
    await _run(() async {
      _cb.onChanged?.call(await AppScope.read(context).api.editPost(t.id, body));
    });
  }

  Future<void> _delete(Post p) async {
    final ok = await confirmDialog(
      context,
      title: p.isShare ? 'シェアを削除しますか？' : '投稿を削除しますか？',
      message: '削除した投稿は表示されなくなります（記録は会社の規定に従って保管されます）。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await AppScope.read(context).api.deletePost(p.id);
      _cb.onDeleted?.call(p.id);
      if (mounted) showInfo(context, '削除しました。');
    });
  }

  Future<void> _report(Post t) async {
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
      await AppScope.read(context).api.report(targetType: 'post', targetId: t.id, reason: reason);
      if (mounted) showInfo(context, '管理者に通報しました。ご協力ありがとうございます。');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    final post = widget.post;
    final t = _target;

    // シェアした人の帯
    Widget? shareHeader;
    if (post.isShare) {
      shareHeader = Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
        child: Row(
          children: [
            Icon(Icons.repeat_rounded, size: 16, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${post.isMine ? 'あなた' : '${post.shownName}さん'}がシェア · ${relativeTime(post.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600),
              ),
            ),
            if (post.canDelete)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _busy ? null : () => _delete(post),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: p.muted),
                ),
              ),
          ],
        ),
      );
    }

    if (t == null) {
      return SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?shareHeader,
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('元の投稿は削除されました。', style: TextStyle(color: p.muted)),
            ),
          ],
        ),
      );
    }

    final canSeeAcks = t.requireAck && (t.isMine || state.isAdmin);
    final menuItems = <PopupMenuEntry<String>>[
      if (t.canEdit) const PopupMenuItem(value: 'edit', child: Text('編集')),
      if (t.canDelete) const PopupMenuItem(value: 'delete', child: Text('削除')),
      if (canSeeAcks) const PopupMenuItem(value: 'acks', child: Text('確認状況を見る')),
      if (!t.isMine) const PopupMenuItem(value: 'report', child: Text('管理者に通報')),
    ];

    final tag = identityTag(context, t.identity);
    final sub = [
      if (t.identity == Identity.real && t.author != null && t.author!.affiliation.isNotEmpty) t.author!.affiliation,
      relativeTime(t.createdAt),
    ].join(' · ');

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openAuthor(t),
          child: AuthorAvatar(item: t, size: 44),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _openAuthor(t),
                    child: Text(
                      t.author != null && t.identity == Identity.real ? displayNameWithStatus(t.author!) : t.shownName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  ?tag,
                  if (t.isCommit) TagPill('COMMIT', small: true, color: Colors.white, background: p.rose),
                  if (t.isAnnouncement) const TagPill('お知らせ', small: true),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
                  if (widget.showChannel && t.channel != null) TagPill(t.channel!.label),
                ],
              ),
            ],
          ),
        ),
        if (menuItems.isNotEmpty)
          SizedBox(
            width: 32,
            height: 32,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              tooltip: 'メニュー',
              icon: Icon(Icons.more_horiz, color: p.muted, size: 20),
              itemBuilder: (_) => menuItems,
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(t);
                  case 'delete':
                    _delete(t);
                  case 'acks':
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AcksScreen(postId: t.id)));
                  case 'report':
                    _report(t);
                }
              },
            ),
          ),
      ],
    );

    final actions = Row(
      children: [
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          count: t.commentCount,
          tooltip: 'コメント',
          onTap: () => _openDetail(t),
        ),
        _ActionButton(
          icon: Icons.repeat_rounded,
          count: t.shareCount,
          tooltip: 'シェア',
          active: t.sharedByMe,
          activeColor: p.success,
          onTap: _busy ? null : () => _shareMenu(t),
        ),
        LikeButton(liked: t.likedByMe, count: t.likeCount, onToggle: () => _toggleLike(t)),
        _ActionButton(
          icon: t.bookmarkedByMe ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          tooltip: t.bookmarkedByMe ? '保存を外す' : '保存',
          active: t.bookmarkedByMe,
          activeColor: p.accent,
          onTap: () => _toggleBookmark(t),
        ),
        const Spacer(),
        if (t.viewCount > 0)
          Tooltip(
            message: '見た人',
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 15, color: p.muted),
                const SizedBox(width: 3),
                Text('${t.viewCount}', style: TextStyle(fontSize: 12, color: p.muted)),
                const SizedBox(width: 4),
              ],
            ),
          ),
      ],
    );

    final needsAck = t.requireAck && !t.ackedByMe;
    return SoftCard(
      padding: EdgeInsets.zero,
      accentBar: needsAck ? p.rose : null,
      onTap: widget.inDetail && !post.isShare ? null : () => _openDetail(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?shareHeader,
          Padding(padding: EdgeInsets.fromLTRB(20, post.isShare ? 12 : 20, 12, 0), child: header),
          if (t.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: RichBody(t.body, style: const TextStyle(fontSize: 15, height: 1.6)),
            ),
          if (t.editedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('（編集済み）', style: TextStyle(fontSize: 12, color: p.muted)),
            ),
          if (t.images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: ImageGrid(images: t.images),
            ),
          if (t.quoteOf != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: QuoteCard(post: t.quoteOf!),
            ),
          if (t.requireAck)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  if (t.ackedByMe)
                    TagPill('✓ 確認済み', color: p.success, background: p.success.withValues(alpha: 0.12))
                  else
                    GradientButton(
                      label: '確認しました',
                      icon: Icons.check_rounded,
                      height: 36,
                      onPressed: _busy ? null : () => _ack(t),
                    ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: canSeeAcks
                        ? () =>
                              Navigator.of(context)
                                  .push(MaterialPageRoute<void>(builder: (_) => AcksScreen(postId: t.id)))
                        : null,
                    child: Text('確認 ${t.ackCount}人', style: TextStyle(fontSize: 12, color: p.muted)),
                  ),
                ],
              ),
            ),
          Padding(padding: const EdgeInsets.fromLTRB(10, 8, 12, 10), child: actions),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.count = 0,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int count;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final color = active ? (activeColor ?? p.accent) : p.muted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 引用された投稿（小さな枠）。タップで元の投稿を開く。
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final tag = identityTag(context, post.identity);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(postId: post.id, initial: post),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.border),
          color: p.borderSoft.withValues(alpha: 0.35),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AuthorAvatar(item: post, size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    post.shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (tag != null) ...[const SizedBox(width: 6), tag],
                const SizedBox(width: 6),
                Text(relativeTime(post.createdAt), style: TextStyle(fontSize: 11.5, color: p.muted)),
              ],
            ),
            if (post.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              RichBody(post.body, maxLines: 6, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            if (post.images.isNotEmpty) ...[const SizedBox(height: 8), ImageGrid(images: post.images, maxHeight: 200)],
          ],
        ),
      ),
    );
  }
}
