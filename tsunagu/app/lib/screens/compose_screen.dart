import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// 投稿の作成。投稿できたら [Post] を返して閉じる。
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.initialChannelId});

  final int? initialChannelId;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const _maxLength = 4000;

  final _body = TextEditingController();
  List<Channel>? _channels;
  int? _channelId;
  bool _announcement = false;
  bool _requireAck = false;
  bool _busy = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await AppScope.read(context).api.channels();
      final postable = all.where((c) => c.canPost && !c.archived).toList();
      if (!mounted) return;
      setState(() {
        _channels = postable;
        _loadError = null;
        final wanted = widget.initialChannelId;
        if (wanted != null && postable.any((c) => c.id == wanted)) {
          _channelId = wanted;
        } else if (postable.isNotEmpty) {
          _channelId = postable.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  bool get _canSubmit =>
      !_busy && _channelId != null && _body.text.trim().isNotEmpty && _body.text.length <= _maxLength;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final post = await AppScope.read(context).api.createPost(
        channelId: _channelId!,
        body: _body.text.trim(),
        announcement: _announcement,
        requireAck: _requireAck,
      );
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_body.text.trim().isEmpty) return true;
    return confirmDialog(
      context,
      title: '下書きを破棄しますか？',
      message: '入力した内容は保存されません。',
      confirmLabel: '破棄',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final channels = _channels;

    Widget content;
    if (_loadError != null) {
      content = MessageView(
        icon: Icons.cloud_off_outlined,
        message: 'チャンネルを読み込めませんでした。',
        actionLabel: '再読み込み',
        onAction: _load,
      );
    } else if (channels == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (channels.isEmpty) {
      content = const MessageView(
        icon: Icons.block,
        message: '投稿できるチャンネルがありません。\nチャンネル一覧から参加してください。',
      );
    } else {
      content = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _channelId,
                  decoration: const InputDecoration(labelText: '投稿先チャンネル', prefixIcon: Icon(Icons.tag)),
                  items: [
                    for (final c in channels)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.isPrivate ? '${c.name}（非公開）' : c.name),
                      ),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _channelId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _body,
                  autofocus: true,
                  enabled: !_busy,
                  minLines: 6,
                  maxLines: 16,
                  maxLength: _maxLength,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '共有したいことを書きましょう。\n@社員コード でメンションできます。',
                    alignLabelWithHint: true,
                  ),
                ),
                if (state.isAdmin) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _announcement,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _announcement = v;
                                  if (!v) _requireAck = false;
                                }),
                          secondary: const Icon(Icons.campaign_outlined),
                          title: const Text('お知らせとして投稿'),
                          subtitle: const Text('チャンネルの全員に通知され、「お知らせ」に表示されます'),
                        ),
                        SwitchListTile(
                          value: _requireAck,
                          onChanged: _busy || !_announcement ? null : (v) => setState(() => _requireAck = v),
                          secondary: const Icon(Icons.fact_check_outlined),
                          title: const Text('「確認しました」ボタンを付ける'),
                          subtitle: const Text('誰が確認したかを一覧で確かめられます'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '社外秘の情報や個人情報（お客様情報など）は投稿しないでください。投稿は会社の管理者が確認できます。',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: _body.text.trim().isEmpty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('新しい投稿'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('投稿する'),
              ),
            ),
          ],
        ),
        body: SafeArea(child: content),
      ),
    );
  }
}
