import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../utils/password_rules.dart';
import '../widgets/common.dart';

/// パスワードの再設定（初回ログイン・仮パスワード再発行後）と任意の変更。
class PasswordChangeScreen extends StatefulWidget {
  /// 仮パスワードでログインした直後に必ず表示する画面。
  const PasswordChangeScreen.required({super.key}) : voluntary = false;

  /// メニューから開く任意のパスワード変更。
  const PasswordChangeScreen.voluntary({super.key}) : voluntary = true;

  final bool voluntary;

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  PasswordPolicy _policy = const PasswordPolicy();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  List<String> _details = const [];

  bool get _needsCurrent => widget.voluntary || !AppScope.read(context).hasTempPassword;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    try {
      final p = await AppScope.read(context).api.passwordPolicy();
      if (mounted) setState(() => _policy = p);
    } on ApiException {
      // 取得できない場合は既定の規則を表示（最終判定はサーバー）。
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _details = const [];
    });
    final state = AppScope.read(context);
    try {
      await state.changePassword(
        currentPassword: _needsCurrent ? _current.text : null,
        newPassword: _new.text,
      );
      if (widget.voluntary && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('パスワードを変更しました。ほかの端末はログアウトされました。')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _details = e.details;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checks = evaluatePassword(_new.text, _confirm.text, _policy);
    final ready = checks.every((c) => c.ok) && (!_needsCurrent || _current.text.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.voluntary ? 'パスワードの変更' : 'パスワードの設定'),
        automaticallyImplyLeading: widget.voluntary,
        actions: [
          if (!widget.voluntary)
            TextButton(
              onPressed: _busy ? null : () => state.logout(),
              child: const Text('ログアウト'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ContentWidth(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.voluntary) ...[
                  Text(
                    '${state.me?.displayName ?? ''} さん、ようこそ。',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '管理者から受け取った仮パスワードは使い続けられません。'
                    'ご自身だけが知っている新しいパスワードを設定してください。',
                  ),
                  const SizedBox(height: 20),
                ],
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!),
                        // サーバーは 1 件目をメッセージにも入れて返すので、同じ文は重ねて出さない
                        for (final d in _details)
                          if (d != _error) Text('・$d'),
                      ],
                    ),
                  ),
                if (_needsCurrent) ...[
                  TextField(
                    controller: _current,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: widget.voluntary ? '現在のパスワード' : '仮パスワード',
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _new,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '新しいパスワード',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'パスワードを表示' : 'パスワードを隠す',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (ready && !_busy) _submit();
                  },
                  decoration: const InputDecoration(
                    labelText: '新しいパスワード（確認）',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in checks)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(
                                  c.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: c.ok ? Colors.green.shade600 : scheme.outline,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(c.label)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          _policy.requireSymbol
                              ? '使える記号: ${_policy.allowedSymbols}'
                              : '記号（${_policy.allowedSymbols}）も使えます。社員コードやメールアドレス、以前のパスワードは使えません。',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: ready && !_busy ? _submit : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.voluntary ? '変更する' : '設定してはじめる'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
