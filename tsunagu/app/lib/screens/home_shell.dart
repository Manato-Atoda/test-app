import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/feed_view.dart';
import '../widgets/glass.dart';
import '../widgets/in_app_banner.dart';
import '../widgets/right_rail.dart';
import '../widgets/watermark.dart';
import 'announcements_screen.dart';
import 'bookmarks_screen.dart';
import 'channels_screen.dart';
import 'commit_screen.dart';
import 'compose_screen.dart';
import 'forest_screens.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';
import 'user_profile_screen.dart';

/// ログイン後のメイン画面。
/// - スマホ: 下のタブ（ホーム / 森 / 通知 / COMMIT / メニュー）
/// - Mac・Windows・iPad 横: 左のサイドバー＋中央＋右の欄（1100px 以上）
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _home = 0;
  static const _forest = 1;
  static const _notifications = 2;
  static const _commit = 3;
  static const _menu = 4;

  int _index = _home;
  Timer? _timer;
  late final FeedController _homeFeed;
  final _forestKey = GlobalKey<ForestScreenState>();
  final _notificationsKey = GlobalKey<NotificationsScreenState>();
  final _commitKey = GlobalKey<CommitScreenState>();

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _homeFeed = FeedController.timeline(state.api);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.refreshBadges();
      state.loadChannels();
      state.markSeen('home');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _homeFeed.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll();
      AppScope.read(context).refreshUnread();
    }
  }

  void _poll() {
    if (!mounted) return;
    AppScope.read(context).refreshBadges();
    _homeFeed.checkNewer();
  }

  void _select(int index) {
    final state = AppScope.read(context);
    if (index == _menu) {
      openMenu(context);
      return;
    }
    if (index == _index) {
      // 同じタブをもう一度押したら最新に更新する。
      switch (index) {
        case _home:
          _homeFeed.refresh();
        case _forest:
          _forestKey.currentState?.refresh();
        case _notifications:
          _notificationsKey.currentState?.refresh();
        case _commit:
          _commitKey.currentState?.refresh();
      }
      return;
    }
    setState(() => _index = index);
    switch (index) {
      case _home:
        state.markSeen('home');
      case _forest:
        state.markSeen('forest');
        _forestKey.currentState?.refresh();
      case _notifications:
        _notificationsKey.currentState?.refresh();
      case _commit:
        state.markSeen('commit');
    }
  }

  Future<void> _compose() async {
    final post = await Navigator.of(context)
        .push<Post>(MaterialPageRoute(builder: (_) => const ComposeScreen(), fullscreenDialog: true));
    if (post != null) _homeFeed.insertNew(post);
  }

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final badges = state.badges;
    final width = MediaQuery.sizeOf(context).width;

    final pages = <Widget>[
      _HomePage(controller: _homeFeed, onCompose: _compose),
      ForestScreen(key: _forestKey),
      NotificationsScreen(key: _notificationsKey),
      CommitScreen(key: _commitKey),
    ];
    final body = IndexedStack(index: _index, children: pages);

    final Widget shell;
    if (width >= 768) {
      shell = Scaffold(
        body: AuroraBackground(
          child: Row(
            children: [
              _SideNav(compact: width < 1000, index: _index, onSelect: _select, onCompose: _compose, onPush: _push),
              VerticalDivider(width: 1, color: context.m.border),
              Expanded(child: body),
              if (width >= 1100) ...[
                VerticalDivider(width: 1, color: context.m.border),
                const SizedBox(width: 320, child: RightRail()),
              ],
            ],
          ),
        ),
      );
    } else {
      final forestColor = badges.forestUrgency == Urgency.calm ? null : urgencyColor(badges.forestUrgency);
      shell = GlassBuilder(
        builder: (context, glass) {
          final height = glass ? GlassTabBarInset.tabBarHeight : _MobileTabBar.barHeight;
          return Scaffold(
            extendBody: true,
            body: GlassTabBarInset(height: height, child: body),
            bottomNavigationBar: glass
                ? GlassTabBar(
                    selectedIndex: _index,
                    onSelected: _select,
                    momentaryIndexes: const {_menu},
                    items: [
                      const GlassTabItem(
                        label: 'ホーム',
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        symbol: 'house',
                        selectedSymbol: 'house.fill',
                      ),
                      GlassTabItem(
                        label: '森',
                        icon: Icons.park_outlined,
                        selectedIcon: Icons.park_rounded,
                        symbol: 'tree',
                        selectedSymbol: 'tree.fill',
                        dot: badges.forestHasNew || badges.forestUrgency != Urgency.calm,
                      ),
                      GlassTabItem(
                        label: '通知',
                        icon: Icons.notifications_outlined,
                        selectedIcon: Icons.notifications_rounded,
                        symbol: 'bell',
                        selectedSymbol: 'bell.fill',
                        badge: badges.notifications,
                      ),
                      GlassTabItem(
                        label: 'COMMIT',
                        icon: Icons.flag_outlined,
                        selectedIcon: Icons.flag_rounded,
                        symbol: 'flag',
                        selectedSymbol: 'flag.fill',
                        dot: badges.commitHasNew,
                      ),
                      const GlassTabItem(
                        label: 'メニュー',
                        icon: Icons.menu_rounded,
                        selectedIcon: Icons.menu_rounded,
                        symbol: 'line.3.horizontal',
                        selectedSymbol: 'line.3.horizontal',
                      ),
                    ],
                  )
                : _MobileTabBar(
                    index: _index,
                    onSelect: _select,
                    items: [
                      _TabSpec('ホーム', Icons.home_outlined, Icons.home_rounded),
                      _TabSpec(
                        '森',
                        Icons.park_outlined,
                        Icons.park_rounded,
                        dot: badges.forestHasNew || badges.forestUrgency != Urgency.calm,
                        dotColor: forestColor,
                      ),
                      _TabSpec(
                        '通知',
                        Icons.notifications_outlined,
                        Icons.notifications_rounded,
                        badge: badges.notifications,
                      ),
                      _TabSpec('COMMIT', Icons.flag_outlined, Icons.flag_rounded, dot: badges.commitHasNew),
                      _TabSpec('メニュー', Icons.menu_rounded, Icons.menu_rounded),
                    ],
                  ),
          );
        },
      );
    }

    return Watermark(
      child: InAppBanner(
        onOpen: (n) {
          state.api.readNotification(n.id).catchError((_) {});
          openNotificationTarget(context, n);
        },
        child: shell,
      ),
    );
  }
}

// ---------------------------------------------------------------- ホーム

class _HomePage extends StatelessWidget {
  const _HomePage({required this.controller, required this.onCompose});

  final FeedController controller;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    final me = state.me;
    final unacked = state.badges.announcementsUnacked;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          padding: const EdgeInsets.all(16),
          onTap: onCompose,
          child: Row(
            children: [
              if (me != null) UserAvatar(user: me, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text('いま、なにしてる？  @ でメンションできます', style: TextStyle(color: p.muted, fontSize: 14)),
              ),
              Icon(Icons.image_outlined, color: p.accent),
            ],
          ),
        ),
        if (unacked > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen())),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: p.likeSoft,
                    border: Border.all(color: p.like.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_rounded, color: p.like),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '確認が必要なお知らせが $unacked 件あります',
                          style: TextStyle(fontWeight: FontWeight.w700, color: p.foreground),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: p.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: GlassAppBar(
        title: Row(
          children: [
            const MLogo(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ホーム'),
                  if (state.company != null)
                    Text(
                      state.company!.name,
                      style: TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          GlassButton(
            symbol: 'magnifyingglass',
            icon: Icons.search,
            tooltip: '投稿を検索',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width >= 768 ? null : GlassComposeButton(onPressed: onCompose),
      body: FeedView(controller: controller, header: header),
    );
  }
}

// ---------------------------------------------------------------- スマホのタブバー（リキッドグラスでないとき）

class _TabSpec {
  _TabSpec(this.label, this.icon, this.selectedIcon, {this.badge = 0, this.dot = false, this.dotColor});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
  final bool dot;
  final Color? dotColor;
}

/// Galaxia のモバイルのタブバー（半透明・ぼかし・上に細い線）。
class _MobileTabBar extends StatelessWidget {
  const _MobileTabBar({required this.index, required this.onSelect, required this.items});

  static const barHeight = 58.0;

  final int index;
  final ValueChanged<int> onSelect;
  final List<_TabSpec> items;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: barHeight + bottom,
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: p.surfaceElevated.withValues(alpha: 0.92),
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              for (final (i, t) in items.indexed)
                Expanded(
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    containedInkWell: true,
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: t.label,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                i == index ? t.selectedIcon : t.icon,
                                color: i == index ? p.accent : p.muted,
                                size: 25,
                              ),
                              if (t.badge > 0)
                                Positioned(right: -12, top: -4, child: CountBadge(t.badge))
                              else if (t.dot)
                                Positioned(right: -2, top: -1, child: NewDot(color: t.dotColor, size: 8)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: i == index ? p.accent : p.muted,
                            ),
                          ),
                        ],
                      ),
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

// ---------------------------------------------------------------- 広い画面のサイドバー

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.compact,
    required this.index,
    required this.onSelect,
    required this.onCompose,
    required this.onPush,
  });

  final bool compact;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCompose;
  final ValueChanged<Widget> onPush;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    final b = state.badges;
    final me = state.me;
    final channels = (state.channels ?? const <Channel>[]).where((c) => c.isMember && !c.archived).toList();

    Widget nav(
      IconData icon,
      IconData activeIcon,
      String label, {
      int? tab,
      VoidCallback? onTap,
      Widget? badge,
      String? hint,
    }) {
      final active = tab != null && tab == index;
      final tile = InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? (tab == null ? null : () => onSelect(tab)),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? p.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(active ? activeIcon : icon, color: active ? p.accent : p.foreground, size: 24),
                  if (compact && badge != null) Positioned(right: -8, top: -6, child: badge),
                ],
              ),
              if (!compact) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                          color: active ? p.accent : p.foreground,
                        ),
                      ),
                      if (hint != null) Text(hint, style: TextStyle(fontSize: 10.5, color: p.muted)),
                    ],
                  ),
                ),
                ?badge,
              ],
            ],
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: compact ? Tooltip(message: label, child: tile) : tile,
      );
    }

    final forestDot = b.forestHasNew || b.forestUrgency != Urgency.calm
        ? NewDot(color: b.forestUrgency == Urgency.calm ? null : urgencyColor(b.forestUrgency))
        : null;

    return SizedBox(
      width: compact ? 76 : 250,
      child: SafeArea(
        right: false,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 16),
          children: [
            Padding(
              padding: EdgeInsets.only(left: compact ? 0 : 8, bottom: 18),
              child: Row(
                mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  const MLogo(size: 36),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    const GradientText('M', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    Text('マル', style: TextStyle(fontSize: 11, color: p.muted)),
                  ],
                ],
              ),
            ),
            nav(Icons.home_outlined, Icons.home_rounded, 'ホーム', tab: 0),
            nav(
              Icons.park_outlined,
              Icons.park_rounded,
              'わからんの森',
              tab: 1,
              badge: forestDot,
              hint: b.forestUrgency.label,
            ),
            nav(
              Icons.notifications_outlined,
              Icons.notifications_rounded,
              '通知',
              tab: 2,
              badge: b.notifications > 0 ? CountBadge(b.notifications) : null,
            ),
            nav(
              Icons.flag_outlined,
              Icons.flag_rounded,
              'COMMIT',
              tab: 3,
              badge: b.commitHasNew ? const NewDot() : null,
            ),
            nav(
              Icons.campaign_outlined,
              Icons.campaign_rounded,
              'お知らせ',
              onTap: () => onPush(const AnnouncementsScreen()),
              badge: b.announcementsUnacked > 0 ? CountBadge(b.announcementsUnacked) : null,
            ),
            nav(
              Icons.bookmark_border_rounded,
              Icons.bookmark_rounded,
              'ブックマーク',
              onTap: () => onPush(const BookmarksScreen()),
            ),
            if (me != null)
              nav(
                Icons.person_outline_rounded,
                Icons.person_rounded,
                'プロフィール',
                onTap: () => onPush(UserProfileScreen(userId: me.id)),
              ),
            nav(Icons.menu_rounded, Icons.menu_rounded, 'メニュー', onTap: () => openMenu(context)),
            const SizedBox(height: 14),
            if (compact)
              Center(
                child: IconButton.filled(
                  tooltip: '投稿',
                  style: IconButton.styleFrom(backgroundColor: p.accent),
                  onPressed: onCompose,
                  icon: const Icon(Icons.edit_outlined),
                ),
              )
            else
              GradientButton(label: '投稿する', icon: Icons.edit_outlined, expand: true, onPressed: onCompose),
            if (!compact) ...[
              SectionLabel(
                'チャンネル',
                trailing: InkWell(
                  onTap: () => onPush(const ChannelsScreen()),
                  child: Text(
                    'すべて',
                    style: TextStyle(fontSize: 12, color: p.accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final c in channels)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onPush(ChannelFeedScreen(channel: c)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(c.emoji ?? '#', style: TextStyle(fontSize: 15, color: p.muted)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: c.unreadCount > 0 ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (c.unreadCount > 0) CountBadge(c.unreadCount),
                      ],
                    ),
                  ),
                ),
              if (me != null) ...[
                const SizedBox(height: 18),
                SoftCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => onPush(UserProfileScreen(userId: me.id)),
                  child: Row(
                    children: [
                      UserAvatar(user: me, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(me.employeeCode, style: TextStyle(fontSize: 11.5, color: p.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
