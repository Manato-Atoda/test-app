import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/auth_image.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/identity_tabs.dart';
import '../widgets/mention_suggestions.dart';
import '../widgets/mindfulness.dart';
import '../widgets/post_card.dart';

enum ComposeMode { post, quote, commit }

/// 投稿・引用・COMMIT の作成。送信できたら [Post] を返して閉じる。
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.initialChannelId}) : mode = ComposeMode.post, quoteOf = null;

  const ComposeScreen.quote({super.key, required Post this.quoteOf})
    : mode = ComposeMode.quote,
      initialChannelId = null;

  const ComposeScreen.commit({super.key}) : mode = ComposeMode.commit, quoteOf = null, initialChannelId = null;

  final ComposeMode mode;
  final int? initialChannelId;
  final Post? quoteOf;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _PendingImage {
  _PendingImage(this.bytes);

  final Uint8List bytes;
  ImageRef? uploaded;
  Object? error;
  bool get uploading => uploaded == null && error == null;
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const _maxLength = 4000;
  static const _maxImages = 4;

  final _body = TextEditingController();
  final _images = <_PendingImage>[];
  List<Channel>? _channels;
  int? _channelId;
  Identity _identity = Identity.real;
  bool _announcement = false;
  bool _requireAck = false;
  bool _busy = false;
  Object? _loadError;
  int _draftCount = 0;

  bool get _isPost => widget.mode == ComposeMode.post;
  bool get _isCommit => widget.mode == ComposeMode.commit;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
    if (_isPost) {
      _loadChannels();
      _loadDraftCount();
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
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
        } else if (postable.isNotEmpty && _channelId == null) {
          _channelId = postable.first.id;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _loadDraftCount() async {
    try {
      final list = await AppScope.read(context).api.drafts();
      if (mounted) setState(() => _draftCount = list.length);
    } catch (_) {
      // 下書きの数が出ないだけ。
    }
  }

  bool get _uploading => _images.any((i) => i.uploading);

  bool get _hasContent => _body.text.trim().isNotEmpty || _images.isNotEmpty;

  bool get _canSubmit {
    if (_busy || _uploading || _images.any((i) => i.error != null)) return false;
    if (_body.text.length > _maxLength) return false;
    final hasText = _body.text.trim().isNotEmpty;
    if (widget.mode == ComposeMode.quote) return hasText;
    if (_isPost && _channelId == null) return false;
    return hasText || _images.isNotEmpty;
  }

  // ---------------------------------------------------------------- 画像

  static String? _imageType(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b.length > 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _pick({bool camera = false}) async {
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    List<XFile> files;
    try {
      if (camera) {
        final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 2048, maxHeight: 2048, imageQuality: 85);
        files = f == null ? const [] : [f];
      } else {
        files = await picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 85, limit: remaining);
      }
    } catch (e) {
      if (mounted) showInfo(context, '画像を選べませんでした（写真へのアクセスが許可されているか確認してください）。');
      return;
    }
    for (final f in files.take(remaining)) {
      final bytes = await f.readAsBytes();
      final type = _imageType(bytes);
      if (!mounted) return;
      if (type == null) {
        showInfo(context, 'この形式の画像は使えません（JPEG / PNG / WebP のみ）。');
        continue;
      }
      if (bytes.length > 8 * 1024 * 1024) {
        showInfo(context, '画像が大きすぎます（8MB まで）。');
        continue;
      }
      final pending = _PendingImage(bytes);
      setState(() => _images.add(pending));
      _upload(pending, type);
    }
  }

  Future<void> _upload(_PendingImage image, String type) async {
    try {
      final ref = await AppScope.read(context).api.upload(image.bytes, type);
      if (mounted) setState(() => image.uploaded = ref);
    } catch (e) {
      if (mounted) setState(() => image.error = e);
    }
  }

  // ---------------------------------------------------------------- 下書き

  Future<void> _saveDraft() async {
    final text = _body.text.trim();
    if (text.isEmpty) return;
    try {
      await AppScope.read(context).api.saveDraft(body: text, identity: _identity, channelId: _channelId);
      if (!mounted) return;
      _body.clear();
      setState(() => _draftCount++);
      showInfo(context, '下書きに追加しました');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _openDrafts() async {
    final api = AppScope.read(context).api;
    final draft = await showModalBottomSheet<Draft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DraftSheet(api: api),
    );
    await _loadDraftCount();
    if (draft == null || !mounted) return;
    if (_body.text.trim().isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: '下書きを呼び出しますか？',
        message: '入力中の本文は下書きの内容に置き換わります。',
        confirmLabel: '呼び出す',
      );
      if (!ok || !mounted) return;
    }
    _body.text = draft.body;
    setState(() {
      if (AppScope.read(context).identityUnavailableReason(draft.identity) == null) _identity = draft.identity;
      final channels = _channels;
      if (draft.channelId != null && channels != null && channels.any((c) => c.id == draft.channelId)) {
        _channelId = draft.channelId;
      }
    });
    // 呼び出した下書きはストックから外す（同じものが二重に残らないように）
    try {
      await api.deleteDraft(draft.id);
      if (mounted) setState(() => _draftCount = _draftCount > 0 ? _draftCount - 1 : 0);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 送信

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final ok = await confirmMindfully(context, _isCommit ? MindfulVariant.commit : MindfulVariant.post);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final api = AppScope.read(context).api;
    final imageIds = [for (final i in _images) i.uploaded!.id];
    try {
      final Post post;
      switch (widget.mode) {
        case ComposeMode.commit:
          post = await api.createCommit(body: _body.text.trim(), imageIds: imageIds);
        case ComposeMode.quote:
          post = await api.createPost(
            channelId: widget.quoteOf!.channel?.id,
            body: _body.text.trim(),
            identity: _identity,
            imageIds: imageIds,
            quoteOf: widget.quoteOf!.id,
          );
        case ComposeMode.post:
          post = await api.createPost(
            channelId: _channelId,
            body: _body.text.trim(),
            announcement: _announcement,
            requireAck: _requireAck,
            identity: _announcement ? Identity.real : _identity,
            imageIds: imageIds,
          );
      }
      if (mounted) Navigator.of(context).pop(post);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (!_hasContent || _busy) {
      Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('入力中の内容があります'),
        content: Text(_isPost ? '下書きに保存しておくと、あとで「下書きストック」から呼び出せます。' : '入力した内容は保存されません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('破棄')),
          if (_isPost && _body.text.trim().isNotEmpty)
            FilledButton(onPressed: () => Navigator.pop(context, 'draft'), child: const Text('下書きに保存')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'draft') await _saveDraft();
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- 画面

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    final me = state.me;
    final title = switch (widget.mode) {
      ComposeMode.post => '新しい投稿',
      ComposeMode.quote => '引用してコメント',
      ComposeMode.commit => 'COMMIT',
    };
    final cta = _isCommit ? 'COMMIT する' : '投稿';
    final hint = switch (widget.mode) {
      ComposeMode.post => 'いま、なにしてる？  @ でメンションできます',
      ComposeMode.quote => 'この投稿について何を伝えたい?',
      ComposeMode.commit => '何を、いつまでに、どこまでやる？  例) 金曜までに採用サイトの初稿を出します',
    };
    final showIdentity = !_isCommit && !_announcement;

    Widget content;
    final channels = _channels;
    if (_isPost && _loadError != null) {
      content = MessageView(
        icon: Icons.cloud_off_outlined,
        message: 'チャンネルを読み込めませんでした。',
        actionLabel: '再読み込み',
        onAction: _loadChannels,
      );
    } else if (_isPost && channels == null) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_isPost && channels!.isEmpty) {
      content = const MessageView(icon: Icons.block, message: '投稿できるチャンネルがありません。\nメニューのチャンネルから参加してください。');
    } else {
      final previewItem = _PreviewAuthor(me: me, identity: showIdentity ? _identity : Identity.real, state: state);
      content = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isCommit) const _CommitIntro(),
                Row(
                  children: [
                    AuthorAvatar(item: previewItem, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        previewItem.shownName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    if (_isPost && channels != null)
                      Flexible(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _channelId,
                            isDense: true,
                            borderRadius: BorderRadius.circular(16),
                            style: TextStyle(color: p.accent, fontWeight: FontWeight.w700, fontSize: 13),
                            items: [
                              for (final c in channels)
                                DropdownMenuItem(value: c.id, child: Text(c.isPrivate ? '${c.label}（非公開）' : c.label)),
                            ],
                            onChanged: _busy ? null : (v) => setState(() => _channelId = v),
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.mode == ComposeMode.quote && widget.quoteOf!.channel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '元の投稿と同じ ${widget.quoteOf!.channel!.label} に投稿されます',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ),
                if (showIdentity) ...[
                  const SizedBox(height: 12),
                  IdentityTabs(value: _identity, enabled: !_busy, onChanged: (v) => setState(() => _identity = v)),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  autofocus: true,
                  enabled: !_busy,
                  minLines: 5,
                  maxLines: 14,
                  maxLength: _maxLength,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 16, height: 1.55),
                  decoration: InputDecoration(hintText: hint, hintMaxLines: 3, alignLabelWithHint: true),
                ),
                MentionSuggestions(controller: _body),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ImageStrip(images: _images, onRemove: (i) => setState(() => _images.removeAt(i))),
                ],
                if (widget.mode == ComposeMode.quote) ...[
                  const SizedBox(height: 12),
                  IgnorePointer(child: QuoteCard(post: widget.quoteOf!)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ToolChip(
                      icon: Icons.image_outlined,
                      label: '画像を追加',
                      onTap: _busy || _images.length >= _maxImages ? null : () => _pick(),
                    ),
                    if (!kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.iOS ||
                            defaultTargetPlatform == TargetPlatform.android))
                      _ToolChip(
                        icon: Icons.photo_camera_outlined,
                        label: 'カメラ',
                        onTap: _busy || _images.length >= _maxImages ? null : () => _pick(camera: true),
                      ),
                    if (_isPost) ...[
                      _ToolChip(
                        icon: Icons.inventory_2_outlined,
                        label: '下書きストック',
                        count: _draftCount,
                        onTap: _busy ? null : _openDrafts,
                      ),
                      _ToolChip(
                        icon: Icons.save_alt_rounded,
                        label: '下書きに追加',
                        onTap: _busy || _body.text.trim().isEmpty ? null : _saveDraft,
                      ),
                    ],
                  ],
                ),
                if (_isPost && state.isAdmin) ...[
                  const SizedBox(height: 12),
                  SoftCard(
                    padding: EdgeInsets.zero,
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
                          subtitle: const Text('チャンネルの全員に通知され、「お知らせ」に表示されます（実名のみ）'),
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
                const SizedBox(height: 14),
                Text(
                  '社外秘の情報や個人情報（お客様情報など）は投稿しないでください。'
                  '匿名・部署名の投稿でも、規程に反する場合は管理者が確認します。',
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(title),
          actions: [
            GlassBuilder(
              builder: (context, glass) => glass
                  ? GlassButton(label: cta, style: GlassButtonStyle.prominent, onPressed: _canSubmit ? _submit : null)
                  : Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GradientButton(
                        label: cta,
                        height: 38,
                        busy: _busy,
                        onPressed: _canSubmit ? _submit : null,
                      ),
                    ),
            ),
          ],
        ),
        body: SafeArea(child: content),
      ),
    );
  }
}

/// 発信者を選んだときの見え方（プレビュー用）。
class _PreviewAuthor with Authored {
  _PreviewAuthor({required Me? me, required this.identity, required AppState state})
    : author = me,
      displayNameRaw = identity == Identity.real ? null : state.identityPreview(identity);

  @override
  final UserSummary? author;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  bool get isMine => true;
}

class _CommitIntro extends StatelessWidget {
  const _CommitIntro();

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: p.likeSoft,
        border: Border.all(color: p.like.withValues(alpha: 0.25)),
      ),
      child: Text(
        '「自分は、いつまでに、どこまでやるのか」を自分の言葉で言い切る場所です。COMMIT は常に実名で公開されます。',
        style: TextStyle(fontSize: 12.5, height: 1.55, color: p.foreground),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, required this.onTap, this.count = 0});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.border),
            color: p.surfaceElevated,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: p.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12.5, color: p.muted, fontWeight: FontWeight.w600),
              ),
              if (count > 0) ...[const SizedBox(width: 6), TagPill('$count', small: true)],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images, required this.onRemove});

  final List<_PendingImage> images;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final img = images[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (img.uploaded != null)
                    AuthImage(img.uploaded!.url)
                  else
                    Image.memory(img.bytes, fit: BoxFit.cover),
                  if (img.uploading)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        ),
                      ),
                    ),
                  if (img.error != null)
                    ColoredBox(
                      color: const Color(0xAA000000),
                      child: Center(
                        child: Text(
                          img.error is ApiException ? 'アップロード\nに失敗' : '失敗',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.likeSoft, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DraftSheet extends StatefulWidget {
  const _DraftSheet({required this.api});

  final ApiClient api;

  @override
  State<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<_DraftSheet> {
  List<Draft>? _drafts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.drafts();
      if (mounted) setState(() => _drafts = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete(Draft d) async {
    try {
      await widget.api.deleteDraft(d.id);
      if (mounted) setState(() => _drafts = _drafts?.where((x) => x.id != d.id).toList());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final drafts = _drafts;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('下書きストック', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            if (drafts == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: _error != null
                    ? Text('読み込めませんでした。', style: TextStyle(color: p.muted))
                    : const Center(child: CircularProgressIndicator()),
              )
            else if (drafts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Text('下書きはありません。書きかけの投稿を「下書きに追加」で残せます。', style: TextStyle(color: p.muted)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (context, i) {
                    final d = drafts[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      title: Text(d.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [d.identity.label, if (d.updatedAt != null) relativeTime(d.updatedAt!)].join(' · '),
                      ),
                      onTap: () => Navigator.pop(context, d),
                      trailing: IconButton(
                        tooltip: '削除',
                        icon: Icon(Icons.delete_outline, color: p.muted),
                        onPressed: () => _delete(d),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
