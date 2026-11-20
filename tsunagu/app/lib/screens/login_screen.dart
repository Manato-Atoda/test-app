import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../services/passkey_flow.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    _company.text = state.savedCompanyCode;
    _loginId.text = state.savedLoginId;
    _notice = state.loginNotice;
    state.clearNotice();
  }

  @override
  void dispose() {
    _company.dispose();
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await AppScope.read(context).login(
        companyCode: _company.text,
        loginId: _loginId.text,
        password: _password.text,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passkeyLogin() async {
    if (_company.text.trim().isEmpty) {
      setState(() => _error = 'パスキーでログインするには、企業コードを入力してください。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await AppScope.read(context).loginWithPasskey(
        companyCode: _company.text,
        loginId: _loginId.text,
      );
    } on PasskeyCancelled {
      // 取り消しは何も出さない。
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverSettings() async {
    final state = AppScope.read(context);
    final controller = TextEditingController(text: state.serverUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('接続先サーバー'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('通常は変更不要です。社内の管理者から指定された場合のみ変更してください。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'サーバーの URL', hintText: 'https://sns.example.co.jp'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('初期値に戻す')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    if (result.trim().isEmpty) {
      await state.resetServerUrl();
    } else {
      await state.setServerUrl(result);
    }
    if (mounted) showInfo(context, '接続先: ${state.serverUrl}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.diversity_3_rounded, size: 56, color: scheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '社内SNS',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  if (_notice != null) _Banner(text: _notice!, color: scheme.secondaryContainer),
                  if (_error != null) _Banner(text: _error!, color: scheme.errorContainer),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _company,
                                enabled: !_busy,
                                textCapitalization: TextCapitalization.characters,
                                autocorrect: false,
                                enableSuggestions: false,
                                // 企業コードは半角英数字のみ。日本語入力（IME）にならないよう英数字キーボードにする
                                keyboardType: TextInputType.visiblePassword,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '企業コード',
                                  prefixIcon: Icon(Icons.apartment_outlined),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? '企業コードを入力してください' : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _loginId,
                                enabled: !_busy,
                                autocorrect: false,
                                enableSuggestions: false,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: const InputDecoration(
                                  labelText: '社員コード または メールアドレス',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? '社員コードまたはメールアドレスを入力してください' : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: _obscure,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _login(),
                                decoration: InputDecoration(
                                  labelText: 'パスワード',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'パスワードを表示' : 'パスワードを隠す',
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'パスワードを入力してください' : null,
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _login,
                                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('ログイン'),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('または', style: theme.textTheme.bodySmall),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _passkeyLogin,
                                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                                icon: const Icon(Icons.key_outlined),
                                label: const Text('パスキーでログイン'),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'パスキーは、ログイン後に「メニュー → パスキー」で登録できます。',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'アカウントは会社の管理者が発行します。\nログインできない場合は、社内の管理者にお問い合わせください。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _serverSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('詳細設定（接続先）'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(text),
    );
  }
}
