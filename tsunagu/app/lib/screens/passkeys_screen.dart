import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../services/passkey_flow.dart';
import '../state/app_scope.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

class PasskeysScreen extends StatefulWidget {
  const PasskeysScreen({super.key});

  @override
  State<PasskeysScreen> createState() => _PasskeysScreenState();
}

class _PasskeysScreenState extends State<PasskeysScreen> {
  List<Passkey>? _passkeys;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).api.passkeys();
      if (mounted) {
        setState(() {
          _passkeys = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _register() async {
    final name = await textInputDialog(
      context,
      title: 'パスキーの名前',
      initialValue: AppConfig.deviceLabel,
      hint: '例: 会社の iPhone',
      confirmLabel: '次へ',
      maxLength: 40,
      maxLines: 1,
    );
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      await state.passkeys.register(name: name);
      await _load();
      await state.refreshMe();
      if (mounted) showInfo(context, 'パスキーを登録しました。次回から「パスキーでログイン」が使えます。');
    } on PasskeyCancelled {
      // 取り消し
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Passkey p) async {
    final ok = await confirmDialog(
      context,
      title: '「${p.name}」を削除しますか？',
      message: 'このパスキーではログインできなくなります。端末やパスワード管理アプリに残っているパスキーは、そちらでも削除してください。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = AppScope.read(context);
    try {
      await state.api.deletePasskey(p.id);
      await _load();
      await state.refreshMe();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _passkeys;
    return Scaffold(
      appBar: GlassAppBar(title: const Text('パスキー')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ContentWidth(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('パスキーとは', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      '顔認証・指紋認証・端末のロック解除だけでログインできる仕組みです。'
                      'パスワードを入力しないため、のぞき見やフィッシングに強く安全です。',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '登録とログインはブラウザの画面で行い、終わるとアプリに戻ります。',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _register,
                      icon: _busy
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text('この端末でパスキーを登録'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (list == null)
            _error != null
                ? MessageView(
                    icon: Icons.cloud_off_outlined,
                    message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
                    actionLabel: '再読み込み',
                    onAction: _load,
                  )
                : const LoadingFooter()
          else if (list.isEmpty)
            const ContentWidth(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('登録済みのパスキーはありません。'),
              ),
            )
          else
            ContentWidth(
              child: Card(
                child: Column(
                  children: [
                    for (final p in list)
                      ListTile(
                        leading: const Icon(Icons.key),
                        title: Text(p.name),
                        subtitle: Text(
                          '登録: ${fullDateTime(p.createdAt)}\n最終利用: ${fullDateTime(p.lastUsedAt)}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: '削除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(p),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
