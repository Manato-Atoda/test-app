import 'package:material_ui/material_ui.dart';

import '../state/app_scope.dart';
import '../widgets/feed_view.dart';
import '../widgets/glass.dart';

/// 会社からのお知らせ（「確認しました」ボタン付きのものを含む）。
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final _state = AppScope.read(context);
  late final FeedController _feed = FeedController.timeline(_state.api, kind: 'announcement');

  @override
  void dispose() {
    _feed.dispose();
    // 確認した数を取り直す
    _state.refreshBadges();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: const GlassAppBar(title: Text('お知らせ')),
      body: FeedView(controller: _feed, emptyMessage: 'お知らせはまだありません', emptyIcon: Icons.campaign_outlined),
    );
  }
}
