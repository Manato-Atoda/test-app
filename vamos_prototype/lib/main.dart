import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/vamos_store.dart';
import 'screens/home_screen.dart';
import 'screens/interview_screens.dart';
import 'screens/my_page_screen.dart';
import 'screens/topic_screens.dart';
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
      // 日本語の字形で表示するため、ロケールを日本語に固定する
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _ContentLoader(),
    );
  }
}

/// 同梱データを読み込んでから、タブ画面を表示する。
class _ContentLoader extends StatefulWidget {
  const _ContentLoader();

  @override
  State<_ContentLoader> createState() => _ContentLoaderState();
}

class _ContentLoaderState extends State<_ContentLoader> {
  late final Future<VamosContent> _content = VamosContent.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VamosContent>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'データを読み込めませんでした。\ntool/import_vamos_data.py を実行してください。\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final content = snapshot.data;
        if (content == null) {
          return const Scaffold(
            backgroundColor: VamosColors.surface,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return VamosShell(content: content);
      },
    );
  }
}

/// 下部タブ（ホーム / インタビュー / トピック / マイページ）
class VamosShell extends StatefulWidget {
  const VamosShell({super.key, required this.content});

  final VamosContent content;

  @override
  State<VamosShell> createState() => _VamosShellState();
}

class _VamosShellState extends State<VamosShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(content: content, onOpenTab: (tab) => setState(() => _tab = tab)),
          InterviewListScreen(interviews: content.interviews),
          TopicListScreen(topics: content.topics),
          MyPageScreen(interviews: content.interviews),
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
