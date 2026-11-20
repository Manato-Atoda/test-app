import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api_client.dart';
import '../data/repository.dart';
import '../theme/vamos_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';

/// 会員登録・ログインの入口（RE_VAMOS と同じく、メールに届く確認コードで認証する）
class AuthEmailScreen extends StatefulWidget {
  const AuthEmailScreen({super.key});

  @override
  State<AuthEmailScreen> createState() => _AuthEmailScreenState();
}

class _AuthEmailScreenState extends State<AuthEmailScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// 日本語入力で全角になった英数字・記号（ａ，＠，．など）を半角にそろえる
  static String _normalizeEmail(String input) => String.fromCharCodes(
        input.trim().runes.map((c) => c >= 0xFF01 && c <= 0xFF5E ? c - 0xFEE0 : c),
      ).replaceAll(RegExp(r'\s'), '').toLowerCase();

  Future<void> _send() async {
    final email = _normalizeEmail(_email.text);
    if (email != _email.text) _email.text = email;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final debugCode = await VamosRepository.instance.requestCode(email);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AuthCodeScreen(email: email, debugCode: debugCode),
      ));
    } on ApiException catch (error) {
      setState(() => _error = error.isOffline ? '${error.message}。モックAPIが起動しているか確認してください。' : error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      kicker: 'Sign in',
      title: 'ログイン・新規登録',
      description: 'メールアドレスに届く6桁の確認コードでログインします。パスワードは必要ありません。',
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: _inputDecoration('メールアドレス', 'name@example.com'),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 20),
        GradientButton(label: _sending ? '送信中…' : '確認コードを送る', onPressed: _sending ? null : _send, expand: true),
      ],
    );
  }
}

/// 確認コードの入力
class AuthCodeScreen extends StatefulWidget {
  const AuthCodeScreen({super.key, required this.email, this.debugCode});

  final String email;

  /// 試作のモックAPIが返す確認コード（本番ではメールでのみ届く）
  final String? debugCode;

  @override
  State<AuthCodeScreen> createState() => _AuthCodeScreenState();
}

class _AuthCodeScreenState extends State<AuthCodeScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final session = await VamosRepository.instance.verify(widget.email, _code.text.trim());
      if (!mounted) return;
      if (session.user.profileCompleted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ログインしました')));
      } else {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debugCode = widget.debugCode;
    return _AuthScaffold(
      kicker: 'Verify',
      title: '確認コードを入力',
      description: '${widget.email} に6桁のコードを送りました。',
      children: [
        if (debugCode != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: VamosColors.primaryLight,
              borderRadius: BorderRadius.circular(VamosRadius.large),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '試作版のため、コードを表示しています：$debugCode',
                    style: const TextStyle(fontSize: 12.5, color: VamosColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _code.text = debugCode),
                  child: const Text('入力する'),
                ),
              ],
            ),
          ),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
          decoration: _inputDecoration('確認コード', '000000'),
          onSubmitted: (_) => _verify(),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 20),
        GradientButton(label: _verifying ? '確認中…' : 'ログイン', onPressed: _verifying ? null : _verify, expand: true),
      ],
    );
  }
}

/// プロフィールの初期設定（RE_VAMOS の onboarding と同じ3ステップ）
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.editing = false});

  /// マイページから編集する場合は true
  final bool editing;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const statuses = [
    ('🎓', '学生・就活中', '新卒での就職を考えている'),
    ('💼', 'インターン希望', 'まずは経験を積みたい'),
    ('🚀', '社会人・転職検討', '次のキャリアを探している'),
    ('👀', '情報収集中', 'まだ決めていない'),
  ];
  static const interests = [
    '営業', '企画・マーケティング', 'エンジニア・IT', 'デザイン・クリエイティブ',
    '事務・管理', '製造・技術', '販売・サービス', '公務員', 'まだ決めていない',
  ];
  static const areas = ['福岡市', '北九州市', '福岡県内（その他）', '九州・山口', '全国どこでも', 'リモート希望'];

  int _step = 0;
  bool _saving = false;
  String? _error;
  late final Set<String> _statuses;
  late final Set<String> _interests;
  late final Set<String> _areas;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final user = VamosRepository.instance.session.value?.user;
    _statuses = {...?user?.statuses};
    _interests = {...?user?.interests};
    _areas = {...?user?.areas};
    _name = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canProceed => switch (_step) {
        0 => _statuses.isNotEmpty,
        1 => _interests.isNotEmpty,
        _ => _name.text.trim().isNotEmpty,
      };

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VamosRepository.instance.updateProfile(
        displayName: _name.text.trim(),
        statuses: _statuses.toList(),
        interests: _interests.toList(),
        areas: _areas.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.editing ? 'プロフィールを更新しました' : 'ようこそ、${_name.text.trim()}さん')),
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(Set<String> set, String value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  @override
  Widget build(BuildContext context) {
    final titles = ['いまの状況を教えてください', '興味のある職種は？', '希望のエリア・働き方'];
    return Scaffold(
      backgroundColor: VamosColors.background,
      appBar: AppBar(
        title: Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS'),
        actions: [
          if (!widget.editing)
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('あとで設定する →'),
            ),
        ],
      ),
      body: ListView(
        padding: Adaptive.horizontal(context, maxWidth: Adaptive.formMaxWidth).copyWith(top: 20, bottom: 40),
        children: [
          VamosCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'ステップ ${_step + 1} / 3',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: VamosColors.primary),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'あなたに合う企業・記事をおすすめするために使います',
                        style: TextStyle(fontSize: 11.5, color: VamosColors.textLight),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(height: 6, color: VamosColors.borderLight),
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 250),
                        widthFactor: (_step + 1) / 3,
                        child: Container(height: 6, decoration: const BoxDecoration(gradient: VamosColors.gradient)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(titles[_step], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'あてはまるものを選んでください（複数選択できます）。',
                  style: TextStyle(fontSize: 13, color: VamosColors.textMuted),
                ),
                const SizedBox(height: 16),
                ...switch (_step) {
                  0 => [
                      for (final (emoji, title, description) in statuses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ChoiceCard(
                            emoji: emoji,
                            title: title,
                            description: description,
                            selected: _statuses.contains(title),
                            onTap: () => _toggle(_statuses, title),
                          ),
                        ),
                    ],
                  1 => [_ChipGroup(options: interests, selected: _interests, onToggle: (v) => _toggle(_interests, v))],
                  _ => [
                      _ChipGroup(options: areas, selected: _areas, onToggle: (v) => _toggle(_areas, v)),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _name,
                        onChanged: (_) => setState(() {}),
                        decoration: _inputDecoration('お名前（ニックネーム可）', '例：あきちゃん'),
                      ),
                    ],
                },
                if (_error != null) _ErrorText(_error!),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (_step > 0)
                      Expanded(child: OutlinePillButton(label: '戻る', onPressed: () => setState(() => _step--))),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        label: _step < 2 ? '次へ' : (_saving ? '保存中…' : (widget.editing ? '保存する' : 'はじめる')),
                        expand: true,
                        onPressed: !_canProceed || _saving
                            ? null
                            : () => _step < 2 ? setState(() => _step++) : _finish(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 絵文字つきの選択カード（RE_VAMOS のオンボーディングと同じ見た目）
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? VamosColors.primaryLight : VamosColors.surface,
          borderRadius: BorderRadius.circular(VamosRadius.large),
          border: Border.all(color: selected ? VamosColors.primary : VamosColors.border, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(description, style: const TextStyle(fontSize: 12, color: VamosColors.textMuted)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: VamosColors.primary),
          ],
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.options, required this.selected, required this.onToggle});

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: [
        for (final option in options)
          GestureDetector(
            onTap: () => onToggle(option),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: selected.contains(option) ? VamosColors.buttonGradient : null,
                color: selected.contains(option) ? null : VamosColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected.contains(option) ? Colors.transparent : VamosColors.border),
              ),
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected.contains(option) ? Colors.white : VamosColors.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.kicker, required this.title, required this.description, required this.children});

  final String kicker;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VamosColors.background,
      appBar: AppBar(title: Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS')),
      body: ListView(
        padding: Adaptive.horizontal(context, maxWidth: Adaptive.formMaxWidth).copyWith(top: 24, bottom: 40),
        children: [
          VamosCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionKicker(kicker),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(description, style: const TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted)),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(message, style: const TextStyle(fontSize: 12.5, color: Color(0xFFE53E3E))),
    );
  }
}

InputDecoration _inputDecoration(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: VamosColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VamosRadius.medium),
        borderSide: const BorderSide(color: VamosColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VamosRadius.medium),
        borderSide: const BorderSide(color: VamosColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VamosRadius.medium),
        borderSide: const BorderSide(color: VamosColors.primary, width: 1.5),
      ),
    );
