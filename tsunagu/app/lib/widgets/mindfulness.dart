import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'brand.dart';

/// 送信前の「ひと呼吸」（Galaxia の post-mindfulness-modal と同じ文言）。
enum MindfulVariant {
  post('送る前に、ひと呼吸', 'ここはお互いを尊重しながら、いい仕事をしていくための場所です。投稿する前に、ちょっとだけ。', '投稿する'),
  question('問いを投げかける前に、ひと呼吸', '誰かが時間と気持ちを使って答えてくれます。質問する前に、ちょっとだけ。', '森に投げかける 🌳'),
  answer('回答を送る前に、ひと呼吸', 'あなたの言葉は、聞き手を勇気づけることも、迷わせることもあります。送る前に、ちょっとだけ。', '回答を送る'),
  commit(
    '言い切る前に、ひと呼吸',
    'COMMIT は、自分で決めたことを自分の言葉にする場所です。大きなことでなくて構いません。'
        '何を、いつまでに、どこまでやるか。ここまで書けているか、ちょっとだけ確かめてから。',
    'COMMIT する',
  );

  const MindfulVariant(this.title, this.intro, this.cta);

  final String title;
  final String intro;
  final String cta;
}

/// 確認して送るなら true。
Future<bool> confirmMindfully(BuildContext context, MindfulVariant variant) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => _MindfulDialog(variant: variant),
  );
  return result ?? false;
}

class _MindfulDialog extends StatelessWidget {
  const _MindfulDialog({required this.variant});

  final MindfulVariant variant;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    Widget item(String icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.5))),
        ],
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x1410B981), Color(0x0D14B8A6), Color(0x146366F1)],
                  ),
                ),
                child: Column(
                  children: [
                    const Text('🌿', style: TextStyle(fontSize: 30)),
                    const SizedBox(height: 6),
                    Text(
                      variant.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      variant.intro,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.6),
                    ),
                    const SizedBox(height: 18),
                    item('🎯', '業務や、チームに関係のある話題ですか?'),
                    item('🤝', '受け取る人の立場や状況にも、想いを向けてみました?'),
                    item('💬', '自分が言われて「あたたかい」と感じる言い方になっていますか?'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: p.borderSoft.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
                          children: [
                            TextSpan(
                              text: '完璧じゃなくて大丈夫。\n',
                              style: TextStyle(fontWeight: FontWeight.w700, color: p.foreground),
                            ),
                            const TextSpan(
                              text:
                                  '豊かなチームは、小さな思いやりの積み重ねからつくられます。\n'
                                  'ここは、強制でも監視でもありません。\n'
                                  'お互いに敬意を持って、業務を円滑に進めていく場所です。',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('見直す')),
                    const SizedBox(width: 10),
                    GradientButton(label: variant.cta, onPressed: () => Navigator.pop(context, true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
