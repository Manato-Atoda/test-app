import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/auth_image.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// プロフィールの編集（アイコン・カバー・あだ名・自己紹介）。
/// 氏名・部署・役職・メールアドレスは管理者が管理する。
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _bio;
  late final TextEditingController _nickname;
  bool _busy = false;

  // 新しく選んだ画像（アップロード済み）。null は変更なし。
  ImageRef? _avatar;
  ImageRef? _cover;
  bool _removeAvatar = false;
  bool _removeCover = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final me = AppScope.read(context).me;
    _bio = TextEditingController(text: me?.bio ?? '');
    _nickname = TextEditingController(text: me?.nickname ?? '');
  }

  @override
  void dispose() {
    _bio.dispose();
    _nickname.dispose();
    super.dispose();
  }

  static String? _imageType(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') return 'image/webp';
    return null;
  }

  Future<ImageRef?> _pickAndUpload({required double maxSize}) async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: maxSize,
        maxHeight: maxSize,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) showInfo(context, '画像を選べませんでした（写真へのアクセスが許可されているか確認してください）。');
      return null;
    }
    if (file == null || !mounted) return null;
    final bytes = await file.readAsBytes();
    final type = _imageType(bytes);
    if (type == null) {
      if (mounted) showInfo(context, 'この形式の画像は使えません（JPEG / PNG / WebP のみ）。');
      return null;
    }
    if (!mounted) return null;
    final api = AppScope.read(context).api;
    setState(() => _uploading = true);
    try {
      return await api.upload(bytes, type);
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final ref = await _pickAndUpload(maxSize: 800);
    if (ref != null && mounted) {
      setState(() {
        _avatar = ref;
        _removeAvatar = false;
      });
    }
  }

  Future<void> _pickCover() async {
    final ref = await _pickAndUpload(maxSize: 2048);
    if (ref != null && mounted) {
      setState(() {
        _cover = ref;
        _removeCover = false;
      });
    }
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final nickname = _nickname.text.trim();
    if (nickname.isNotEmpty && nickname == state.me?.displayName) {
      showInfo(context, 'あだ名は氏名と同じにはできません。');
      return;
    }
    setState(() => _busy = true);
    try {
      final me = await state.api.updateProfile(
        bio: _bio.text.trim(),
        nickname: nickname,
        avatarUploadId: _avatar?.id,
        coverUploadId: _cover?.id,
        removeAvatar: _removeAvatar,
        removeCover: _removeCover,
      );
      state.updateMe(me);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('プロフィールを保存しました。')));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).me;
    final p = context.m;
    final coverUrl = _removeCover ? null : (_cover?.url ?? me?.coverUrl);
    final avatarUser = me == null
        ? null
        : UserSummary(
            id: me.id,
            displayName: me.displayName,
            employeeCode: me.employeeCode,
            department: me.department,
            title: me.title,
            avatarColor: me.avatarColor,
            role: me.role,
            status: me.status,
            avatarUrl: _removeAvatar ? null : (_avatar?.url ?? me.avatarUrl),
          );
    final saveEnabled = !_busy && !_uploading;
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('プロフィールを編集'),
        actions: [
          GlassBuilder(
            builder: (context, glass) => glass
                ? GlassButton(label: '保存', style: GlassButtonStyle.prominent, onPressed: saveEnabled ? _save : null)
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GradientButton(label: '保存', height: 38, busy: _busy, onPressed: saveEnabled ? _save : null),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ContentWidth(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // カバーとアイコン
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coverUrl != null)
                          AuthImage(coverUrl)
                        else
                          const DecoratedBox(decoration: BoxDecoration(gradient: brandGradient)),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Row(
                            children: [
                              if (coverUrl != null)
                                _ImageButton(
                                  icon: Icons.delete_outline,
                                  tooltip: 'カバーを外す',
                                  onTap: () => setState(() {
                                    _cover = null;
                                    _removeCover = true;
                                  }),
                                ),
                              const SizedBox(width: 6),
                              _ImageButton(icon: Icons.photo_camera_outlined, tooltip: 'カバーを変更', onTap: _pickCover),
                            ],
                          ),
                        ),
                        if (_uploading)
                          const ColoredBox(
                            color: Color(0x55000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                ),
                if (avatarUser != null)
                  Transform.translate(
                    offset: const Offset(16, -36),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _pickAvatar,
                          child: Stack(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: p.background, shape: BoxShape.circle),
                                child: UserAvatar(user: avatarUser, size: 80),
                              ),
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: p.accent,
                                  child: const Icon(Icons.photo_camera_outlined, size: 15, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (avatarUser.avatarUrl != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _avatar = null;
                              _removeAvatar = true;
                            }),
                            child: const Text('アイコンを外す'),
                          ),
                      ],
                    ),
                  ),
                if (me != null)
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(
                          [me.affiliation, me.employeeCode].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _nickname,
                  enabled: !_busy,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'あだ名（匿名で投稿するときの表示名）',
                    hintText: '例) ぽんず',
                    prefixIcon: Icon(Icons.theater_comedy_outlined),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '匿名で投稿・コメントすると、氏名の代わりにこのあだ名が表示されます。'
                    'あだ名は他の社員には誰のものかわからないようになっています（プロフィールにも表示されません）。'
                    'ただし、規程に反する投稿の通報があった場合は、管理者が本人を確認することがあります。',
                    style: TextStyle(fontSize: 12, color: p.muted, height: 1.55),
                  ),
                ),
                TextField(
                  controller: _bio,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: '自己紹介',
                    hintText: '担当業務、得意なこと、社内で気軽に聞いてほしいことなど',
                    alignLabelWithHint: true,
                  ),
                ),
                Text('氏名・部署・役職・メールアドレスの変更は、社内の管理者に依頼してください。', style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageButton extends StatelessWidget {
  const _ImageButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
