import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/interview_screens.dart';
import 'screens/search_screen.dart';
import 'screens/topic_screens.dart';
import 'widgets/common.dart';

/// 通知やディープリンクから画面を開くための Navigator
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// アプリ内の URL（/interviews/<slug>、/topics/<id>、/search）から画面を作る。
Route<void>? routeFor(String? name) {
  final uri = name == null ? null : Uri.tryParse(name);
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final settings = RouteSettings(name: name);

  if (segments.length == 2 && segments.first == 'interviews') {
    return MaterialPageRoute<void>(settings: settings, builder: (_) => InterviewDetailScreen(slug: segments[1]));
  }
  if (segments.length == 2 && segments.first == 'topics') {
    final id = int.tryParse(segments[1]);
    if (id != null) {
      return MaterialPageRoute<void>(settings: settings, builder: (_) => TopicDetailScreen(id: id));
    }
  }
  if (segments.length == 1 && segments.first == 'search') {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => SearchScreen(initialKeyword: uri.queryParameters['q'] ?? ''),
    );
  }
  return null;
}

Route<void> notFoundRoute(RouteSettings settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Scaffold(
        appBar: AppBar(),
        body: const ErrorView(message: 'ページが見つかりませんでした'),
      ),
    );

/// 通知などのリンク（vamos://app/interviews/<slug>）を開く。
void openLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return;
  final path = uri.scheme == AppConfig.linkScheme
      ? (uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path)
      : link;
  rootNavigatorKey.currentState?.pushNamed(path);
}
