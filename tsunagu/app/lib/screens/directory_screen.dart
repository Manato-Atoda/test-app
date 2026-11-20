import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'user_profile_screen.dart';

/// 社員名簿（在籍者のみ）。
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UserSummary>? _users;
  Object? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final id = ++_requestId;
    try {
      final users = await AppScope.read(context).api.directory(q: _query.text.trim());
      if (!mounted || id != _requestId) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    final theme = Theme.of(context);
    Widget list;
    if (users == null) {
      list = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: _load,
            )
          : const Center(child: CircularProgressIndicator());
    } else if (users.isEmpty) {
      list = const MessageView(icon: Icons.person_search_outlined, message: '該当する社員はいません。');
    } else {
      list = ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, i) {
          final u = users[i];
          return ContentWidth(
            child: ListTile(
              leading: UserAvatar(user: u),
              title: Text(u.displayName),
              subtitle: Text(
                [if (u.affiliation.isNotEmpty) u.affiliation, u.employeeCode].join(' · '),
              ),
              trailing: u.isAdmin
                  ? Text('管理者', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary))
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: u.id)),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('社員名簿')),
      body: Column(
        children: [
          ContentWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '氏名・部署・社員コードで検索',
                  isDense: true,
                ),
              ),
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }
}
