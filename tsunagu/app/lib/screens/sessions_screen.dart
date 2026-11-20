import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// ログイン中の端末の一覧と、ほかの端末のログアウト。
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<SessionInfo>? _sessions;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).api.sessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _revoke(SessionInfo s) async {
    final ok = await confirmDialog(
      context,
      title: 'この端末をログアウトさせますか？',
      message: '${s.client}（${fullDateTime(s.createdAt)} にログイン）',
      confirmLabel: 'ログアウトさせる',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.deleteSession(s.id);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  IconData _icon(String client) {
    final c = client.toLowerCase();
    if (c.contains('iphone') || c.contains('ios') || c.contains('android')) return Icons.smartphone;
    if (c.contains('mac') || c.contains('windows') || c.contains('linux')) return Icons.laptop;
    return Icons.language;
  }

  @override
  Widget build(BuildContext context) {
    final list = _sessions;
    final theme = Theme.of(context);
    Widget body;
    if (list == null) {
      body = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: _load,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  '心当たりのない端末がある場合は、ログアウトさせたうえでパスワードを変更し、管理者に連絡してください。',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            ContentWidth(
              child: Card(
                child: Column(
                  children: [
                    for (final s in list)
                      ListTile(
                        leading: Icon(_icon(s.client)),
                        title: Text(s.current ? '${s.client}（この端末）' : s.client),
                        subtitle: Text(
                          '${s.authMethodLabel}でログイン · ${fullDateTime(s.createdAt)}\n'
                          '最終利用: ${fullDateTime(s.lastSeenAt)}',
                        ),
                        isThreeLine: true,
                        trailing: s.current
                            ? null
                            : IconButton(
                                tooltip: 'ログアウトさせる',
                                icon: const Icon(Icons.logout),
                                onPressed: () => _revoke(s),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(appBar: GlassAppBar(title: const Text('ログイン中の端末')), body: body);
  }
}
