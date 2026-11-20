import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'announcements_screen.dart';
import 'bookmarks_screen.dart';
import 'channels_screen.dart';
import 'directory_screen.dart';
import 'guidelines_screen.dart';
import 'passkeys_screen.dart';
import 'password_change_screen.dart';
import 'profile_edit_screen.dart';
import 'sessions_screen.dart';
import 'user_profile_screen.dart';

/// メニューを下から開く（全画面）。開くとチャンネルの未読も取り直す。
/// 項目から開いた画面は、メニューの上に重ねる（戻るとメニューに戻る）。
Future<void> openMenu(BuildContext context) {
  AppScope.read(context).loadChannels();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const GlassScaffold(
        scrollUnderBars: true,
        appBar: GlassAppBar(title: Text('メニュー')),
        body: MenuContent(),
      ),
    ),
  );
}

void _push(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

Future<void> openAdminConsole(BuildContext context) async {
  final state = AppScope.read(context);
  final uri = Uri.parse('${state.serverUrl}/admin');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    showInfo(context, '管理コンソールを開けませんでした（${uri.toString()}）。');
  }
}

/// メニューの中身（プロフィール・チャンネル・各種設定・ログアウト）。
class MenuContent extends StatelessWidget {
  const MenuContent({super.key});

  Future<void> _logoutAll(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'すべての端末からログアウトしますか？',
      message: 'この端末を含め、ログイン中のすべての端末（スマートフォン・PC）からログアウトします。端末を紛失したときなどに使ってください。',
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
    final p = context.m;
    final channels = (state.channels ?? const <Channel>[]).where((c) => c.isMember && !c.archived).toList();

    void open(Widget screen) => _push(context, screen);

    Widget item(IconData icon, String label, VoidCallback onTap, {Widget? trailing, String? subtitle, Color? color}) =>
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? Icon(Icons.chevron_right, color: p.muted),
          onTap: onTap,
        );

    // 内容は上下のバーの下まで流れるので、その分の余白をとる
    return SingleChildScrollView(
      padding: scrollPadding(context, const EdgeInsets.fromLTRB(12, 4, 12, 32)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (me != null)
            SoftCard(
              padding: const EdgeInsets.all(16),
              onTap: () => open(UserProfileScreen(userId: me.id)),
              child: Row(
                children: [
                  UserAvatar(user: me, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        if (me.affiliation.isNotEmpty)
                          Text(me.affiliation, style: TextStyle(color: p.muted, fontSize: 13)),
                        Text(
                          '${company?.name ?? ''} · ${me.employeeCode}${me.isAdmin ? ' · 管理者' : ''}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: p.muted),
                ],
              ),
            ),
          SectionLabel(
            'チャンネル',
            trailing: TextButton(onPressed: () => open(const ChannelsScreen()), child: const Text('すべて見る')),
          ),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (state.channels == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (channels.isEmpty)
                  ListTile(title: const Text('参加中のチャンネルはありません'), onTap: () => open(const ChannelsScreen())),
                for (final c in channels)
                  ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 28,
                      child: Center(
                        child: c.emoji != null
                            ? Text(c.emoji!, style: const TextStyle(fontSize: 18))
                            : Icon(c.isPrivate ? Icons.lock_outline : Icons.tag, size: 20),
                      ),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    trailing: c.unreadCount > 0 ? CountBadge(c.unreadCount) : null,
                    onTap: () => open(ChannelFeedScreen(channel: c)),
                  ),
              ],
            ),
          ),
          const SectionLabel('社内'),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                item(
                  Icons.campaign_outlined,
                  'お知らせ',
                  () => open(const AnnouncementsScreen()),
                  trailing: state.badges.announcementsUnacked > 0
                      ? CountBadge(state.badges.announcementsUnacked)
                      : null,
                ),
                item(Icons.bookmark_border_rounded, 'ブックマーク', () => open(const BookmarksScreen())),
                item(Icons.groups_outlined, '社員名簿', () => open(const DirectoryScreen())),
                item(Icons.rule_outlined, '利用ガイドライン', () => open(const GuidelinesScreen.view())),
              ],
            ),
          ),
          const SectionLabel('アカウント'),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                item(
                  Icons.edit_note_outlined,
                  'プロフィールを編集',
                  () => open(const ProfileEditScreen()),
                  subtitle: 'アイコン・カバー・あだ名・自己紹介',
                ),
                item(
                  Icons.key_outlined,
                  'パスキー',
                  () => open(const PasskeysScreen()),
                  subtitle: (me?.passkeyCount ?? 0) > 0 ? '${me!.passkeyCount}件 登録済み' : 'パスワードなしでログインできます',
                ),
                item(Icons.password_outlined, 'パスワードの変更', () => open(const PasswordChangeScreen.voluntary())),
                item(Icons.devices_outlined, 'ログイン中の端末', () => open(const SessionsScreen())),
              ],
            ),
          ),
          if (state.isAdmin) ...[
            const SectionLabel('管理者'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: item(
                Icons.admin_panel_settings_outlined,
                '管理コンソールを開く',
                () => openAdminConsole(context),
                subtitle: 'アカウント発行・チャンネル・通報・監査ログ・AI インサイト（ブラウザ）',
                trailing: Icon(Icons.open_in_new, color: p.muted, size: 18),
              ),
            ),
          ],
          const SectionLabel('ログアウト'),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                item(Icons.logout, 'ログアウト', () => _logout(context), trailing: const SizedBox.shrink()),
                item(
                  Icons.phonelink_erase_outlined,
                  'すべての端末からログアウト',
                  () => _logoutAll(context),
                  color: Theme.of(context).colorScheme.error,
                  trailing: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '接続先: ${state.serverUrl}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}
