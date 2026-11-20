import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';

/// 社員のプロフィールと最近の投稿。
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final int userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _profile;
  Object? _error;

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

  void _replace(Post post) {
    final p = _profile;
    if (p == null) return;
    setState(() {
      _profile = UserProfile(user: p.user, posts: [for (final x in p.posts) x.id == post.id ? post : x]);
    });
  }

  void _remove(int id) {
    final p = _profile;
    if (p == null) return;
    setState(() => _profile = UserProfile(user: p.user, posts: p.posts.where((x) => x.id != id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final theme = Theme.of(context);
    Widget body;
    if (profile == null) {
      body = _error != null
          ? MessageView(
              icon: Icons.person_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: _load,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final u = profile.user;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            ContentWidth(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      UserAvatar(user: u, size: 72),
                      const SizedBox(height: 12),
                      Text(displayNameWithStatus(u),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if (u.affiliation.isNotEmpty) Text(u.affiliation),
                      const SizedBox(height: 4),
                      Text('社員コード ${u.employeeCode}', style: theme.textTheme.bodySmall),
                      if (u.email.isNotEmpty) SelectableText(u.email, style: theme.textTheme.bodySmall),
                      if (u.bio.isNotEmpty) ...[
                        const Divider(height: 28),
                        Align(alignment: Alignment.centerLeft, child: Text(u.bio)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ContentWidth(
              child: Text('最近の投稿',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            if (profile.posts.isEmpty)
              const ContentWidth(child: Text('表示できる投稿はありません。')),
            for (final p in profile.posts)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PostCard(key: ValueKey(p.id), post: p, onChanged: _replace, onDeleted: _remove),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('プロフィール')), body: body);
  }
}
