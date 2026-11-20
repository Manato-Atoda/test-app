import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/feed_view.dart';
import 'channels_screen.dart';
import 'compose_screen.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';

/// ログイン後のメイン画面。広い画面は左のレール、狭い画面は下のバーで切り替える。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _timer;
  late final FeedController _homeFeed;
  late final FeedController _announcements;
  final _notificationsKey = GlobalKey<NotificationsScreenState>();

  @override
  void initState() {
    super.initState();
    final api = AppScope.read(context).api;
    _homeFeed = FeedController(api: api);
    _announcements = FeedController(api: api, kind: 'announcement');
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _homeFeed.dispose();
    _announcements.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _poll();
  }

  void _poll() {
    if (!mounted) return;
    AppScope.read(context).refreshUnread();
  }

  void _select(int index) {
    if (index == _index) {
      // 同じタブをもう一度押したら最新に更新する。
      if (index == 0) _homeFeed.refresh();
      if (index == 2) _announcements.refresh();
      if (index == 3) _notificationsKey.currentState?.refresh();
      return;
    }
    setState(() => _index = index);
    if (index == 3) _notificationsKey.currentState?.refresh();
  }

  Future<void> _compose() async {
    final post = await Navigator.of(context).push<Post>(
      MaterialPageRoute(builder: (_) => const ComposeScreen(), fullscreenDialog: true),
    );
    if (post == null) return;
    _homeFeed.insertNew(post);
    if (post.isAnnouncement) _announcements.insertNew(post);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final unread = state.unreadCount;
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final pages = <Widget>[
      _FeedPage(
        title: 'ホーム',
        controller: _homeFeed,
        onCompose: _compose,
        emptyMessage: 'まだ投稿はありません。\n右下のボタンから最初の投稿をしてみましょう。',
      ),
      const ChannelsScreen(),
      _FeedPage(
        title: 'お知らせ',
        controller: _announcements,
        emptyMessage: 'お知らせはまだありません。',
      ),
      NotificationsScreen(key: _notificationsKey),
      const MenuScreen(),
    ];

    final destinations = <({IconData icon, IconData selected, String label, int badge})>[
      (icon: Icons.home_outlined, selected: Icons.home, label: 'ホーム', badge: 0),
      (icon: Icons.tag, selected: Icons.tag, label: 'チャンネル', badge: 0),
      (icon: Icons.campaign_outlined, selected: Icons.campaign, label: 'お知らせ', badge: 0),
      (icon: Icons.notifications_outlined, selected: Icons.notifications, label: '通知', badge: unread),
      (icon: Icons.menu, selected: Icons.menu, label: 'メニュー', badge: 0),
    ];

    Widget icon(IconData data, int badge) => badge > 0
        ? Badge(label: Text(badge > 99 ? '99+' : '$badge'), child: Icon(data))
        : Icon(data);

    final body = IndexedStack(index: _index, children: pages);

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(Icons.diversity_3_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
                      const SizedBox(height: 4),
                      Text('つなぐ', style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: icon(d.icon, d.badge),
                      selectedIcon: icon(d.selected, d.badge),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: icon(d.icon, d.badge),
              selectedIcon: icon(d.selected, d.badge),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _FeedPage extends StatelessWidget {
  const _FeedPage({
    required this.title,
    required this.controller,
    required this.emptyMessage,
    this.onCompose,
  });

  final String title;
  final FeedController controller;
  final String emptyMessage;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final company = AppScope.of(context).company;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (company != null)
              Text(company.name, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '投稿を検索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: onCompose == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onCompose,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('投稿'),
            ),
      body: FeedView(controller: controller, emptyMessage: emptyMessage),
    );
  }
}
