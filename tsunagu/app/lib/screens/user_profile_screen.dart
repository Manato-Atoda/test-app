import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/auth_image.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/post_card.dart';
import 'forest_screens.dart';
import 'profile_edit_screen.dart';

/// 社員のプロフィール（カバー・アイコン・自己紹介・投稿 / COMMIT / 質問）。
/// 匿名・部署名で書いたものはここには出ない。
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final int userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _profile;
  Object? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await AppScope.read(context).api.user(widget.userId);
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<Post> _map(List<Post> list, Post post) => [
    for (final x in list)
      if (x.id == post.id) post else if (x.quoteOf?.id == post.id) x.copyWith(quoteOf: post) else x,
  ];

  void _replace(Post post) {
    final p = _profile;
    if (p == null) return;
    setState(() => _profile = p.copyWith(posts: _map(p.posts, post), commits: _map(p.commits, post)));
  }

  void _remove(int id) {
    final p = _profile;
    if (p == null) return;
    setState(
      () => _profile = p.copyWith(
        posts: p.posts.where((x) => x.id != id).toList(),
        commits: p.commits.where((x) => x.id != id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final p = context.m;
    final me = AppScope.of(context).me;
    if (profile == null) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('プロフィール')),
        body: _error != null
            ? MessageView(
                icon: Icons.person_off_outlined,
                message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
                actionLabel: '再読み込み',
                onAction: _load,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final u = profile.user;
    final isMe = me?.id == u.id;
    final callbacks = PostCallbacks(onChanged: _replace, onDeleted: _remove);
    final items = switch (_tab) {
      0 => [
        for (final post in profile.posts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PostCard(key: ValueKey(post.id), post: post, callbacks: callbacks),
          ),
      ],
      1 => [
        for (final post in profile.commits)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PostCard(key: ValueKey(post.id), post: post, callbacks: callbacks),
          ),
      ],
      _ => [for (final q in profile.questions) QuestionCard(question: q, onChanged: _load)],
    };
    final emptyText = switch (_tab) {
      0 => '表示できる投稿はありません',
      1 => 'まだ COMMIT はありません',
      _ => 'まだ質問はありません',
    };

    return GlassScaffold(
      scrollUnderBars: true,
      appBar: const GlassAppBar(),
      body: Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 32),
            children: [
              // カバー（未設定ならブランドのグラデーション）
              SizedBox(
                height: 170 + MediaQuery.paddingOf(context).top - kToolbarHeight,
                child: u.coverUrl != null
                    ? AuthImage(u.coverUrl!, fit: BoxFit.cover)
                    : const DecoratedBox(decoration: BoxDecoration(gradient: brandGradient)),
              ),
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -44),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: p.background, shape: BoxShape.circle),
                              child: UserAvatar(user: u, size: 88),
                            ),
                            const Spacer(),
                            if (isMe)
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Navigator.of(context)
                                      .push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()));
                                  _load();
                                },
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('プロフィールを編集'),
                              ),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayNameWithStatus(u),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            if (u.affiliation.isNotEmpty)
                              Text(u.affiliation, style: TextStyle(color: p.muted, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              '社員コード ${u.employeeCode}${u.isAdmin ? ' · 管理者' : ''}',
                              style: TextStyle(color: p.muted, fontSize: 12.5),
                            ),
                            if (u.email.isNotEmpty)
                              SelectableText(u.email, style: TextStyle(color: p.muted, fontSize: 12.5)),
                            if (u.bio.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(u.bio, style: const TextStyle(fontSize: 14.5, height: 1.6)),
                            ],
                            const SizedBox(height: 16),
                            SegmentedButton<int>(
                              segments: [
                                ButtonSegment(value: 0, label: Text('投稿 ${profile.posts.length}')),
                                ButtonSegment(value: 1, label: Text('COMMIT ${profile.commits.length}')),
                                ButtonSegment(value: 2, label: Text('質問 ${profile.questions.length}')),
                              ],
                              selected: {_tab},
                              showSelectedIcon: false,
                              onSelectionChanged: (s) => setState(() => _tab = s.first),
                            ),
                          ],
                        ),
                      ),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(emptyText, style: TextStyle(color: p.muted)),
                          ),
                        ),
                      ...items,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
