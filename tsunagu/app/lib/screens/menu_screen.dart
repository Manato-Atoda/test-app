import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'directory_screen.dart';
import 'guidelines_screen.dart';
import 'passkeys_screen.dart';
import 'password_change_screen.dart';
import 'profile_edit_screen.dart';
import 'sessions_screen.dart';
import '../widgets/glass.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openAdmin(BuildContext context) async {
    final state = AppScope.read(context);
    final uri = Uri.parse('${state.serverUrl}/admin');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showInfo(context, '管理コンソールを開けませんでした（${uri.toString()}）。');
    }
  }

  Future<void> _logoutAll(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'すべての端末からログアウトしますか？',
      message:
          'この端末を含め、ログイン中のすべての端末（スマートフォン・PC）からログアウトします。'
          '端末を紛失したときなどに使ってください。',
      confirmLabel: 'すべてログアウト',
      destructive: true,
    );
    if (ok && context.mounted) await AppScope.read(context).logout(everywhere: true);
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmDialog(context, title: 'ログアウトしますか？', message: 'この端末からログアウトします。', confirmLabel: 'ログアウト');
    if (ok && context.mounted) await AppScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.me;
    final company = state.company;
    final theme = Theme.of(context);

    return GlassScaffold(
      scrollUnderBars: true,
      appBar: const GlassAppBar(title: Text('メニュー')),
      // 余白はバーの高さに合わせるので、Scaffold の中の context で作る
      body: Builder(
        builder: (context) => ListView(
          padding: scrollPadding(context, const EdgeInsets.only(bottom: 32)),
          children: [
            if (me != null)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          UserAvatar(user: me, size: 56),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  me.displayName,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (me.affiliation.isNotEmpty) Text(me.affiliation),
                                Text(
                                  '${company?.name ?? ''}  社員コード ${me.employeeCode}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                if (me.isAdmin)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '管理者',
                                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _Group(
              title: '社内',
              children: [
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('社員名簿'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const DirectoryScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: const Text('利用ガイドライン'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const GuidelinesScreen.view()),
                ),
              ],
            ),
            _Group(
              title: 'アカウント',
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('プロフィール（自己紹介）'),
                  subtitle: const Text('氏名・部署・役職は管理者が登録します'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const ProfileEditScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('パスキー'),
                  subtitle: Text((me?.passkeyCount ?? 0) > 0 ? '${me!.passkeyCount}件 登録済み' : 'パスワードなしでログインできます'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const PasskeysScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('パスワードの変更'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const PasswordChangeScreen.voluntary()),
                ),
                ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('ログイン中の端末'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, const SessionsScreen()),
                ),
              ],
            ),
            if (state.isAdmin)
              _Group(
                title: '管理者',
                children: [
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('管理コンソールを開く'),
                    subtitle: const Text('アカウント発行・チャンネル・通報・監査ログ（ブラウザで開きます）'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _openAdmin(context),
                  ),
                ],
              ),
            _Group(
              title: 'ログアウト',
              children: [
                ListTile(leading: const Icon(Icons.logout), title: const Text('ログアウト'), onTap: () => _logout(context)),
                ListTile(
                  leading: Icon(Icons.phonelink_erase_outlined, color: theme.colorScheme.error),
                  title: Text('すべての端末からログアウト', style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () => _logoutAll(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '接続先: ${state.serverUrl}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
            Card(child: Column(children: children)),
          ],
        ),
      ),
    );
  }
}
