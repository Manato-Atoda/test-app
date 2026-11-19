import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/vamos_store.dart';
import '../theme/vamos_theme.dart';
import '../widgets/common.dart';
import 'interview_screens.dart';

/// マイページ（試作のため、ログインや保存内容の永続化はしない）
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key, required this.interviews});

  final List<Interview> interviews;

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  static const _statuses = [
    ('🎓', '学生・就活中', '新卒での就職を考えている'),
    ('💼', 'インターン希望', 'まずは経験を積みたい'),
    ('🚀', '社会人・転職検討', '次のキャリアを探している'),
    ('👀', '情報収集中', 'まだ決めていない'),
  ];

  final Set<int> _selected = {};

  void _notReady() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('会員機能は試作版では準備中です')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const VamosSliverAppBar(),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          sliver: SliverList.list(
            children: [
              _GuestCard(onSignUp: _notReady, onLogin: _notReady),
              const SizedBox(height: 28),
              _OnboardingCard(
                statuses: _statuses,
                selected: _selected,
                onToggle: (index) => setState(() {
                  if (!_selected.remove(index)) _selected.add(index);
                }),
              ),
              const SizedBox(height: 28),
              const SectionKicker('Saved'),
              const SizedBox(height: 8),
              const Text('保存したインタビュー', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              ValueListenableBuilder<Set<String>>(
                valueListenable: savedInterviews,
                builder: (context, saved, _) {
                  final items = widget.interviews.where((i) => saved.contains(i.slug)).toList();
                  if (items.isEmpty) {
                    return const VamosCard(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'まだありません。インタビューの右上にある保存ボタンで、ここに追加できます。',
                        style: TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final interview in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: VamosCard(
                            onTap: () => openInterview(context, interview),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(VamosRadius.medium),
                                  child: SizedBox(width: 96, height: 54, child: AssetPhoto(interview.thumbnail)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    interview.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.onSignUp, required this.onLogin});

  final VoidCallback onSignUp;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return VamosCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              InitialAvatar('ゲスト', size: 44),
              SizedBox(width: 12),
              Text('ゲストさん', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '無料登録すると、気になる企業をフォローして、説明会やインターンの最新情報を受け取れます。',
            style: TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 16),
          GradientButton(label: '新規登録（準備中）', onPressed: onSignUp, expand: true),
          const SizedBox(height: 10),
          OutlinePillButton(label: 'ログイン', onPressed: onLogin, expand: true),
        ],
      ),
    );
  }
}

/// サイトのオンボーディング（絵文字の選択カード＋ステップ表示）を再現したもの
class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.statuses, required this.selected, required this.onToggle});

  final List<(String, String, String)> statuses;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return VamosCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('ステップ 1 / 3', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: VamosColors.primary)),
              SizedBox(width: 10),
              Expanded(
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
                FractionallySizedBox(
                  widthFactor: 1 / 3,
                  child: Container(height: 6, decoration: const BoxDecoration(gradient: VamosColors.gradient)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('いまの状況を教えてください', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'あてはまるものを選んでください（複数選択できます）。',
            style: TextStyle(fontSize: 13, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 16),
          for (final (index, (emoji, title, description)) in statuses.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChoiceCard(
                emoji: emoji,
                title: title,
                description: description,
                selected: selected.contains(index),
                onTap: () => onToggle(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
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
