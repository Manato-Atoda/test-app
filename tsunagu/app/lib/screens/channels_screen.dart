import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/feed_view.dart';
import 'compose_screen.dart';
import '../widgets/glass.dart';

/// チャンネル一覧（参加中 / 参加できる公開チャンネル）。
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Channel>? _channels;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).api.channels();
      if (mounted) {
        setState(() {
          _channels = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _replace(Channel c) {
    final list = _channels;
    if (list == null) return;
    setState(() => _channels = [for (final x in list) x.id == c.id ? c : x]);
  }

  Future<void> _open(Channel c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChannelFeedScreen(channel: c, onChanged: _replace)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channels;
    Widget body;
    if (channels == null) {
      body = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: _load,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final joined = channels.where((c) => c.isMember && !c.archived).toList();
      final others = channels.where((c) => !c.isMember && !c.archived).toList();
      final archived = channels.where((c) => c.archived).toList();
      // 余白はバーの高さに合わせるので、Scaffold の中の context で作る
      body = Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: _load,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollPadding(context, const EdgeInsets.only(bottom: 24)),
            children: [
              _Section('参加中のチャンネル', joined, onTap: _open),
              if (others.isNotEmpty) _Section('参加できるチャンネル', others, onTap: _open),
              if (archived.isNotEmpty) _Section('アーカイブ済み', archived, onTap: _open),
            ],
          ),
        ),
      );
    }
    return GlassScaffold(scrollUnderBars: true, appBar: const GlassAppBar(title: Text('チャンネル')), body: body);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.channels, {required this.onTap});

  final String title;
  final List<Channel> channels;
  final ValueChanged<Channel> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          if (channels.isEmpty)
            const ListTile(title: Text('ありません')),
          for (final c in channels)
            ListTile(
              leading: Icon(c.isPrivate ? Icons.lock_outline : (c.companyWide ? Icons.apartment : Icons.tag)),
              title: Text(c.name),
              subtitle: Text(
                [
                  if (c.companyWide) '全社',
                  if (c.isPrivate) '非公開',
                  if (c.adminsOnly) '管理者のみ投稿',
                  '${c.memberCount}人',
                  if (c.description.isNotEmpty) c.description,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onTap(c),
            ),
        ],
      ),
    );
  }
}

/// チャンネルごとのタイムライン。
class ChannelFeedScreen extends StatefulWidget {
  const ChannelFeedScreen({super.key, required this.channel, this.onChanged});

  final Channel channel;
  final ValueChanged<Channel>? onChanged;

  @override
  State<ChannelFeedScreen> createState() => _ChannelFeedScreenState();
}

class _ChannelFeedScreenState extends State<ChannelFeedScreen> {
  late Channel _channel = widget.channel;
  late final FeedController _feed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _feed = FeedController(api: AppScope.read(context).api, channelId: widget.channel.id);
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  Future<void> _toggleMembership() async {
    if (_channel.isMember) {
      final ok = await confirmDialog(
        context,
        title: '「${_channel.name}」から退出しますか？',
        message: 'ホームのタイムラインにこのチャンネルの投稿が表示されなくなります。',
        confirmLabel: '退出',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.read(context).api;
      final c = _channel.isMember ? await api.leaveChannel(_channel.id) : await api.joinChannel(_channel.id);
      if (!mounted) return;
      setState(() => _channel = c);
      widget.onChanged?.call(c);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose() async {
    final post = await Navigator.of(context).push<Post>(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(initialChannelId: _channel.id),
        fullscreenDialog: true,
      ),
    );
    if (post != null) _feed.insertNew(post);
  }

  @override
  Widget build(BuildContext context) {
    final c = _channel;
    final canToggle = !c.companyWide && !c.archived && (!c.isPrivate || c.isMember);
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: GlassAppBar(
        title: Text('#${c.name}'),
        actions: [
          if (canToggle)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GlassButton(
                label: c.isMember ? '退出' : '参加する',
                style: c.isMember ? GlassButtonStyle.outlined : GlassButtonStyle.prominent,
                onPressed: _busy ? null : _toggleMembership,
              ),
            ),
        ],
      ),
      floatingActionButton: c.canPost && !c.archived ? GlassComposeButton(onPressed: _compose) : null,
      body: FeedView(
        controller: _feed,
        showChannel: false,
        header: c.description.isEmpty && !c.archived
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      [
                        if (c.description.isNotEmpty) c.description,
                        if (c.archived) 'このチャンネルはアーカイブされています（閲覧のみ）。',
                      ].join('\n'),
                    ),
                  ),
                ),
              ),
        emptyMessage: 'このチャンネルにはまだ投稿がありません。',
      ),
    );
  }
}
