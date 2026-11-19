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
    _repository.refresh();
    PushService.init(onOpenLink: openLink);
    PushService.isEnabled().then((enabled) {
      if (enabled) _repository.notificationsEnabled.value = true;
    });
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
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(content: feed, onOpenTab: (tab) => setState(() => _tab = tab)),
          InterviewListScreen(feed: feed),
          TopicListScreen(feed: feed),
          MyPageScreen(feed: feed),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: VamosColors.borderLight))),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (tab) => setState(() => _tab = tab),
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'ホーム'),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum_rounded),
              label: 'インタビュー',
            ),
            NavigationDestination(
              icon: Icon(Icons.lightbulb_outline_rounded),
              selectedIcon: Icon(Icons.lightbulb_rounded),
              label: 'トピック',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'マイページ',
            ),
          ],
        ),
      ),
    );
  }
}
