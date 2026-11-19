import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/vamos_store.dart';
import '../theme/vamos_theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/content_blocks.dart';

void openInterview(BuildContext context, Interview interview) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => InterviewDetailScreen(interview: interview),
  ));
}

/// 企業インタビュー一覧
class InterviewListScreen extends StatelessWidget {
  const InterviewListScreen({super.key, required this.interviews});

  final List<Interview> interviews;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const VamosSliverAppBar(),
        SliverToBoxAdapter(
          child: PageIntro(
            kicker: 'Interview',
            title: '企業インタビュー',
            description: 'Vamos の学生リポーターが、参加企業を直接取材。求人票だけでは見えない“はたらくリアル”を、対談形式でお届けします。',
            count: interviews.length,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          sliver: SliverList.separated(
            itemCount: interviews.length,
            separatorBuilder: (_, _) => const SizedBox(height: 18),
            itemBuilder: (context, index) => InterviewCard(
              interview: interviews[index],
              onTap: () => openInterview(context, interviews[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// 企業インタビューの詳細（吹き出しの対談形式）
class InterviewDetailScreen extends StatelessWidget {
  const InterviewDetailScreen({super.key, required this.interview});

  final Interview interview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VamosColors.surface,
      appBar: AppBar(
        title: Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS'),
        actions: [
          ValueListenableBuilder<Set<String>>(
            valueListenable: savedInterviews,
            builder: (context, saved, _) {
              final isSaved = saved.contains(interview.slug);
              return IconButton(
                tooltip: isSaved ? '保存を解除' : '保存する',
                icon: Icon(
                  isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: isSaved ? VamosColors.primary : VamosColors.text,
                ),
                onPressed: () {
                  toggleSaved(interview.slug);
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                      content: Text(isSaved ? '保存を解除しました' : 'マイページに保存しました'),
                      duration: const Duration(seconds: 2),
                    ));
                },
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          const Align(alignment: Alignment.centerLeft, child: CategoryChip('インタビュー', style: ChipStyle.filled)),
          const SizedBox(height: 14),
          Text(interview.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.5)),
          const SizedBox(height: 14),
          _MetaRow(interview: interview),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(VamosRadius.large),
            child: AspectRatio(aspectRatio: 16 / 9, child: AssetPhoto(interview.thumbnail)),
          ),
          const SizedBox(height: 26),
          for (final block in interview.blocks) ContentBlockView(block),
          const SizedBox(height: 24),
          const _EndCta(),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.interview});

  final Interview interview;

  @override
  Widget build(BuildContext context) {
    const meta = TextStyle(fontSize: 12.5, color: VamosColors.textMuted);
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InitialAvatar(interview.author, size: 30),
            const SizedBox(width: 8),
            Text(interview.author, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: VamosColors.textLight),
            const SizedBox(width: 4),
            Text(interview.date, style: meta),
          ],
        ),
        if (interview.readMinutes > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: VamosColors.textLight),
              const SizedBox(width: 4),
              Text('約${interview.readMinutes}分', style: meta),
            ],
          ),
      ],
    );
  }
}

/// 記事末尾の案内帯（サイトの sg-endcta に相当）
class _EndCta extends StatelessWidget {
  const _EndCta();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: VamosColors.primaryLight,
        borderRadius: BorderRadius.circular(VamosRadius.large),
      ),
      child: Column(
        children: [
          const Text(
            'あなたの“いい会社”を、Vamosで。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.6),
          ),
          const SizedBox(height: 8),
          const Text(
            '気になる企業をフォローすると、新しいインタビューや説明会の情報が届きます。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.7, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: '企業をフォロー（準備中）',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('フォロー機能は試作版では準備中です')),
            ),
          ),
        ],
      ),
    );
  }
}
