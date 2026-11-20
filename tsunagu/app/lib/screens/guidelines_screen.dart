import 'package:material_ui/material_ui.dart';

import '../state/app_scope.dart';
import '../widgets/common.dart';

/// 社内SNS利用ガイドライン（会社の管理者が設定）。
class GuidelinesScreen extends StatefulWidget {
  /// 同意が必要なときの画面（同意するまで先に進めない）。
  const GuidelinesScreen.accept({super.key}) : readOnly = false;

  /// メニューから読むだけの画面。
  const GuidelinesScreen.view({super.key}) : readOnly = true;

  final bool readOnly;

  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).acceptGuidelines();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final company = state.company;
    final text = (company?.guidelines.trim().isNotEmpty ?? false)
        ? company!.guidelines
        : 'ガイドラインはまだ設定されていません。';

    return Scaffold(
      appBar: AppBar(
        title: const Text('利用ガイドライン'),
        automaticallyImplyLeading: widget.readOnly,
        actions: [
          if (!widget.readOnly)
            TextButton(onPressed: _busy ? null : () => state.logout(), child: const Text('ログアウト')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ContentWidth(
                  maxWidth: 640,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.readOnly) ...[
                        Text(
                          '${company?.name ?? ''} の社内SNSを使う前に、次のガイドラインをお読みください。',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!widget.readOnly)
              ContentWidth(
                maxWidth: 640,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        value: _agreed,
                        onChanged: _busy ? null : (v) => setState(() => _agreed = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('ガイドラインを読み、内容に同意します'),
                      ),
                      FilledButton(
                        onPressed: _agreed && !_busy ? _accept : null,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: const Text('同意してはじめる'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
