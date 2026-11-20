import 'package:material_ui/material_ui.dart';

import '../state/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _bio;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bio = TextEditingController(text: AppScope.read(context).me?.bio ?? '');
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      final me = await state.api.updateBio(_bio.text.trim());
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('プロフィール'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GlassButton(label: '保存', style: GlassButtonStyle.prominent, onPressed: _busy ? null : _save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (me != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(user: me),
                    title: Text(me.displayName),
                    subtitle: Text([me.affiliation, me.employeeCode].where((s) => s.isNotEmpty).join(' · ')),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bio,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: '自己紹介',
                    hintText: '担当業務、得意なこと、社内で気軽に聞いてほしいことなど',
                    alignLabelWithHint: true,
                  ),
                ),
                Text(
                  '氏名・部署・役職・メールアドレスの変更は、社内の管理者に依頼してください。',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
