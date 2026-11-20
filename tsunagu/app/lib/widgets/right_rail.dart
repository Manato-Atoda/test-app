import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'brand.dart';
import 'common.dart';

/// 広い画面の右側の欄（今日のメンバー・盛り上がってる投稿・最近のリアクション）。
class RightRail extends StatefulWidget {
  const RightRail({super.key});

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> {
  Highlights? _data;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final h = await AppScope.read(context).api.highlights();
      if (mounted) setState(() => _data = h);
    } catch (_) {
      // 右の欄は補助なので、失敗しても何も出さない。
    }
  }

  void _openPost(int id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostDetailScreen(postId: id)));

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final h = _data;
    Widget box(String title, Widget child, {String? note}) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                ),
                if (note != null) Text(note, style: TextStyle(fontSize: 11, color: p.muted)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
    Widget empty(String text) => Text(text, style: TextStyle(fontSize: 12.5, color: p.muted));

    return ListView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 24),
      children: [
        box(
          '今日のメンバー',
          h == null || h.membersToday.isEmpty
              ? empty('まだ活動がありません')
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final u in h.membersToday)
                      Tooltip(
                        message: u.displayName,
                        child: GestureDetector(
                          onTap: () =>
                              Navigator.of(context)
                                  .push(MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: u.id))),
                          child: UserAvatar(user: u, size: 34),
                        ),
                      ),
                  ],
                ),
          note: h == null ? null : '直近1週間でアクティブ ${h.active7d}人',
        ),
        box(
          '盛り上がってる投稿',
          h == null || h.trending.isEmpty
              ? empty('まだリアクションが集まっていません')
              : Column(
                  children: [
                    for (final t in h.trending)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openPost(t.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.excerpt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1.45),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${t.displayName} · ♥ ${t.likeCount} · 💬 ${t.commentCount}',
                                style: TextStyle(fontSize: 11.5, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          note: '直近1週間',
        ),
        box(
          '最近のリアクション',
          h == null || h.recentReactions.isEmpty
              ? empty('まだコメントがありません')
              : Column(
                  children: [
                    for (final r in h.recentReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openPost(r.postId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                r.type == 'like' ? Icons.favorite_rounded : Icons.chat_bubble_rounded,
                                size: 16,
                                color: r.type == 'like' ? p.like : p.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.type == 'like'
                                          ? 'あなたの投稿に いいね が付きました'
                                          : '${r.actor?.displayName ?? r.displayName ?? '誰か'} さんがコメント',
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                    if (r.excerpt.isNotEmpty)
                                      Text(
                                        r.excerpt,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: p.muted),
                                      ),
                                    Text(relativeTime(r.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
