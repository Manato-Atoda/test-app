import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_router.dart';
import 'data/repository.dart';
import 'screens/home_screen.dart';
import 'screens/interview_screens.dart';
import 'screens/my_page_screen.dart';
import 'screens/topic_screens.dart';
import 'services/push_service.dart';
import 'theme/vamos_theme.dart';
import 'widgets/glass.dart';

void main() {
  runApp(const VamosApp());
}

class VamosApp extends StatelessWidget {
  const VamosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAMOS',
      debugShowCheckedModeBanner: false,
      theme: buildVamosTheme(),
      navigatorKey: rootNavigatorKey,
      // 日本語の字形で表示するため、ロケールを日本語に固定する
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // ディープリンク（vamos://app/interviews/<slug>）で起動した場合も、下にタブ画面を置く
      onGenerateInitialRoutes: (initialRoute) => [
        MaterialPageRoute<void>(settings: const RouteSettings(name: '/'), builder: (_) => const RootScreen()),
        if (routeFor(initialRoute) case final route?) route,
      ],
      onGenerateRoute: (settings) => routeFor(settings.name),
      onUnknownRoute: notFoundRoute,
    );
  }
}

/// データを読み込み、通知の受け取りを準備してからタブ画面を表示する。
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _repository = VamosRepository.instance;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // リキッドグラスが使えるか確認（iOS 26 以降で「透明度を下げる」がオフ）
    await GlassSupport.init();
    // ログイン状態・保存した記事を戻してから、最新のデータを取得する
    await _repository.restore();
    await _repository.refresh();
    await PushService.init(onOpenLink: openLink);
    // 「設定」アプリで通知をオフにされていたら、表示もオフにする
    if (_repository.notificationsEnabled.value && !await PushService.isEnabled()) {
      _repository.notificationsEnabled.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Feed?>(
      valueListenable: _repository.feed,
      builder: (context, feed, _) {
        if (feed == null) {
          return const Scaffold(
            backgroundColor: VamosColors.surface,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return VamosShell(feed: feed);
      },
    );
  }
}

/// 下部タブ（ホーム / インタビュー / トピック / マイページ）
class VamosShell extends StatefulWidget {
  const VamosShell({super.key, required this.feed});

  final Feed feed;

  @override
  State<VamosShell> createState() => _VamosShellState();
}

class _VamosShellState extends State<VamosShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    return Scaffold(
      // 記事がタブバーの下まで流れ、ガラス越しに透けて見えるようにする
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(content: feed, onOpenTab: (tab) => setState(() => _tab = tab)),
          InterviewListScreen(feed: feed, active: _tab == 1),
          TopicListScreen(feed: feed, active: _tab == 2),
          MyPageScreen(feed: feed),
        ],
      ),
      bottomNavigationBar: GlassTabBar(
        selectedIndex: _tab,
        onSelected: (tab) => setState(() => _tab = tab),
        items: const [
          GlassTabItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'ホーム',
            symbol: 'house',
            selectedSymbol: 'house.fill',
          ),
          GlassTabItem(
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum_rounded,
            label: 'インタビュー',
            symbol: 'bubble.left.and.bubble.right',
            selectedSymbol: 'bubble.left.and.bubble.right.fill',
          ),
          GlassTabItem(
            icon: Icons.lightbulb_outline_rounded,
            selectedIcon: Icons.lightbulb_rounded,
            label: 'トピック',
            symbol: 'lightbulb',
            selectedSymbol: 'lightbulb.fill',
          ),
          GlassTabItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'マイページ',
            symbol: 'person',
            selectedSymbol: 'person.fill',
          ),
        ],
      ),
    );
  }
}
