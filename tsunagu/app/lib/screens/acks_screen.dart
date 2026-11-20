import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// お知らせの確認状況（投稿者・管理者のみ）。
class AcksScreen extends StatefulWidget {
  const AcksScreen({super.key, required this.postId});

  final int postId;

  @override
  State<AcksScreen> createState() => _AcksScreenState();
}

class _AcksScreenState extends State<AcksScreen> {
  AckStatus? _status;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await AppScope.read(context).api.acks(widget.postId);
      if (mounted) {
        setState(() {
          _status = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('確認状況')),
        body: _error != null
            ? MessageView(
                icon: Icons.error_outline,
                message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
                actionLabel: '再読み込み',
                onAction: _load,
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final total = s.acked.length + s.notAcked.length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('確認状況（${s.acked.length} / $total 人）'),
          bottom: TabBar(
            tabs: [
              Tab(text: '未確認 ${s.notAcked.length}'),
              Tab(text: '確認済み ${s.acked.length}'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _UserList(users: s.notAcked, empty: '全員が確認しました。', onRefresh: _load),
            _UserList(users: s.acked, empty: 'まだ誰も確認していません。', onRefresh: _load),
          ],
        ),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.users, required this.empty, required this.onRefresh});

  final List<UserSummary> users;
  final String empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: users.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [const SizedBox(height: 80), MessageView(icon: Icons.groups_outlined, message: empty)],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: users.length,
              itemBuilder: (context, i) {
                final u = users[i];
                return ContentWidth(
                  child: ListTile(
                    leading: UserAvatar(user: u),
                    title: Text(u.displayName),
                    subtitle: Text([if (u.affiliation.isNotEmpty) u.affiliation, u.employeeCode].join(' · ')),
                  ),
                );
              },
            ),
    );
  }
}
