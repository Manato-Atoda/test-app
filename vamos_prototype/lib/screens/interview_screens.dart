import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/external_actions.dart';
import '../theme/vamos_theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/content_blocks.dart';
import '../widgets/glass.dart';
import 'search_screen.dart';

void openInterview(BuildContext context, Interview interview) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    settings: RouteSettings(name: '/interviews/${interview.slug}'),
    builder: (_) => InterviewDetailScreen(slug: interview.slug, preview: interview),
  ));
}

/// 企業インタビュー一覧（引っ張って更新）
class InterviewListScreen extends StatelessWidget {
  const InterviewListScreen({super.key, required this.feed});

  final Feed feed;

  @override
  Widget build(BuildContext context) {
    final interviews = feed.interviews;
    final repository = VamosRepository.instance;
    return RefreshIndicator(
      onRefresh: repository.refresh,
      edgeOffset: 60,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const VamosSliverAppBar(actions: [SearchButton()]),
          if (feed.isOffline) SliverToBoxAdapter(child: OfflineBanner.forFeed(feed, onRetry: repository.refresh)),
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
          const BottomBarSpacer(),
        ],
      ),
    );
  }
}

/// 企業インタビューの詳細（吹き出しの対談形式）。本文は API から取得する。
class InterviewDetailScreen extends StatefulWidget {
  const InterviewDetailScreen({super.key, required this.slug, this.preview});

  final String slug;

  /// 一覧から開いたときの概要（本文の読み込み中に先に表示する）
  final Interview? preview;

  @override
  State<InterviewDetailScreen> createState() => _InterviewDetailScreenState();
}

class _InterviewDetailScreenState extends State<InterviewDetailScreen> {
  late Future<Interview> _future = _load();

  Future<Interview> _load() => VamosRepository.instance.interview(widget.slug);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VamosColors.surface,
      // 本文がヘッダーの下まで流れ、ガラス越しに透けて見えるようにする
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS'),
        actions: [
          FutureBuilder<Interview>(
            future: _future,
            builder: (context, snapshot) {
              final interview = snapshot.data ?? widget.preview;
              return Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: '共有する',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: interview == null ? null : () => shareInterview(buttonContext, interview),
                ),
              );
            },
          ),
          _SaveButton(slug: widget.slug),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<Interview>(
        future: _future,
        builder: (context, snapshot) {
          final interview = snapshot.data ?? widget.preview;
          if (snapshot.hasError && interview == null) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          if (interview == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 48),
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
              if (snapshot.data == null && snapshot.hasError)
                ErrorView(message: snapshot.error.toString(), onRetry: () => setState(() => _future = _load()))
              else if (snapshot.data == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                for (final block in interview.blocks) ContentBlockView(block),
                const SizedBox(height: 24),
                const _EndCta(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final repository = VamosRepository.instance;
    return ValueListenableBuilder<Set<String>>(
      valueListenable: repository.saved,
      builder: (context, saved, _) {
        final isSaved = saved.contains(slug);
        return IconButton(
          tooltip: isSaved ? '保存を解除' : '保存する',
          icon: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: isSaved ? VamosColors.primary : VamosColors.text,
          ),
          onPressed: () {
            repository.toggleSaved(slug);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text(isSaved ? '保存を解除しました' : 'マイページに保存しました'),
                duration: const Duration(seconds: 2),
              ));
          },
        );
      },
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
