import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'forest_screens.dart';
import 'post_detail_screen.dart';
import '../widgets/glass.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => NotificationsScreenState();
}

class NotificationsScreenState extends State<NotificationsScreen> {
  final List<AppNotification> _items = [];
  int? _nextBefore;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AppScope.read(context).api.notifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.notifications);
        _nextBefore = page.nextBefore;
        _loaded = true;
      });
      AppScope.read(context).setUnread(page.unreadCount);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBefore;
    if (_loading || before == null) return;
    setState(() => _loading = true);
    try {
      final page = await AppScope.read(context).api.notifications(before: before);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.notifications);
        _nextBefore = page.nextBefore;
      });
    } catch (e) {
      // 失敗したら自動では読み直さない（引っ張って更新でやり直せる）。
      _nextBefore = null;
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readAll() async {
    try {
      await AppScope.read(context).api.readAllNotifications();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          _items[i] = _items[i].markRead();
        }
      });
      AppScope.read(context).setUnread(0);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(int index) async {
    final n = _items[index];
    final state = AppScope.read(context);
    if (!n.read) {
      setState(() => _items[index] = n.markRead());
      state.setUnread(state.unreadCount > 0 ? state.unreadCount - 1 : 0);
      state.api.readNotification(n.id).catchError((_) {});
    }
    await openNotificationTarget(context, n);
  }

  IconData _icon(String type) => notificationIcon(type);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = _items.any((n) => !n.read);
    Widget body;
    if (!_loaded) {
      body = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: refresh,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      // 余白はバーの高さに合わせるので、Scaffold の中の context で作る
      body = Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: scrollPadding(context, EdgeInsets.zero),
                  children: const [
                    SizedBox(height: 80),
                    MessageView(icon: Icons.notifications_none, message: '通知はありません。'),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: scrollPadding(context, EdgeInsets.zero),
                  itemCount: _items.length + (_nextBefore != null ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _items.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
                      return const LoadingFooter();
                    }
                    final n = _items[i];
                    return ContentWidth(
                      child: ListTile(
                        tileColor: n.read ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                        leading: n.actor != null
                            ? Badge(
                                backgroundColor: theme.colorScheme.primary,
                                isLabelVisible: true,
                                label: Icon(_icon(n.type), size: 10, color: Colors.white),
                                child: UserAvatar(user: n.actor!),
                              )
                            : Icon(_icon(n.type)),
                        title: Text(n.description),
                        subtitle: Text(
                          [if (n.excerpt.isNotEmpty) n.excerpt, relativeTime(n.createdAt)].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: n.excerpt.isNotEmpty,
                        onTap: () => _open(i),
                      ),
                    );
                  },
                ),
        ),
      );
    }
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: GlassAppBar(
        title: const Text('通知'),
        actions: [if (hasUnread) GlassButton(label: 'すべて既読', onPressed: _readAll)],
      ),
      body: body,
    );
  }
}

IconData notificationIcon(String type) => switch (type) {
  'comment' => Icons.chat_bubble_outline,
  'mention' => Icons.alternate_email,
  'announcement' => Icons.campaign_outlined,
  'answer' => Icons.park_outlined,
  'answer_comment' => Icons.forum_outlined,
  'share' => Icons.repeat_rounded,
  'quote' => Icons.format_quote_rounded,
  _ => Icons.notifications_outlined,
};

/// 通知の飛び先（投稿 / 森の質問）を開く。
Future<void> openNotificationTarget(BuildContext context, AppNotification n) async {
  final target = n.target;
  if (target == null) return;
  final Widget screen = target.type == 'question'
      ? QuestionDetailScreen(questionId: target.id)
      : PostDetailScreen(postId: target.id);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}
