import 'package:flutter/material.dart';

import '../config.dart';
import '../data/repository.dart';
import '../services/external_actions.dart';
import '../theme/vamos_theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import 'interview_screens.dart';
import 'search_screen.dart';
import 'topic_screens.dart';

/// ホーム（サイトのトップページに相当）
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.content, required this.onOpenTab});

  final Feed content;

  /// 下のタブを切り替える（1: インタビュー、2: トピック）
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final interviews = content.interviews;
    final repository = VamosRepository.instance;
    return RefreshIndicator(
      onRefresh: repository.refresh,
      edgeOffset: 60,
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const VamosSliverAppBar(actions: [SearchButton()]),
        if (content.isOffline) SliverToBoxAdapter(child: OfflineBanner.forFeed(content, onRetry: repository.refresh)),
        SliverToBoxAdapter(child: _HeroCarousel(content: content)),
        SliverToBoxAdapter(
          child: _Section(
            title: 'Interview',
            description: 'Vamos 運営チームの学生メンバーが、参加企業を直接取材。\n求人票だけでは見えない「働くリアル」を、学生目線でお届けします。',
            child: Column(
              children: [
                for (final interview in interviews.take(3)) ...[
                  InterviewCard(interview: interview, onTap: () => openInterview(context, interview)),
                  const SizedBox(height: 18),
                ],
                OutlinePillButton(label: 'すべて見る  →', onPressed: () => onOpenTab(1)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Section(
            title: 'トピック',
            description: '就活・転職にすぐ役立つ情報と、いま知っておきたいニュース。',
            child: Column(
              children: [
                for (final topic in content.topics.take(5))
                  TopicRow(topic: topic, onTap: () => openTopic(context, topic)),
                const SizedBox(height: 20),
                OutlinePillButton(label: 'トピックをもっと見る', onPressed: () => onOpenTab(2)),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _CtaBand()),
        const SliverToBoxAdapter(child: _Footer()),
        const BottomBarSpacer(),
      ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// 最新インタビューのスライド（サイトのヒーローカルーセルに相当）
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.content});

  final Feed content;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.content.interviews.take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9.6,
            child: PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () => openInterview(context, items[index]),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(VamosRadius.large),
                      boxShadow: VamosShadows.card,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(VamosRadius.large),
                      child: AssetPhoto(items[index].thumbnail),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: i == _page ? VamosColors.gradient : null,
                    color: i == _page ? null : VamosColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「仕事を選ぶとき、知りたいことは、きっと同じだ。」の帯
class _CtaBand extends StatelessWidget {
  const _CtaBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 44),
      color: VamosColors.ctaBand,
      child: Column(
        children: [
          const Text(
            '仕事を選ぶとき、\n知りたいことは、\nきっと同じだ。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.6),
          ),
          const SizedBox(height: 14),
          const Text(
            'Vamos は、学生編集部と Galaxia がつくる、働くすべての人のための Web メディア。会員登録なしで、そのまま読めます。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 22),
          GradientButton(label: 'Vamos について知る  →', onPressed: () => showAboutVamos(context)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      decoration: const BoxDecoration(
        color: VamosColors.surfaceMuted,
        border: Border(top: BorderSide(color: VamosColors.primary, width: 2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vamos',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: VamosColors.primary),
          ),
          SizedBox(height: 10),
          Text(
            '企業の「発信力」から、自分に合う会社と出会うメディア。就活・転職のヒントを、福岡・北九州から全国へ。',
            style: TextStyle(fontSize: 12.5, height: 1.8, color: VamosColors.textMuted),
          ),
          SizedBox(height: 16),
          Text(
            '※ 試作版です。記事は RE_VAMOS の公開データのコピーを表示しています。',
            style: TextStyle(fontSize: 11, color: VamosColors.textLight),
          ),
        ],
      ),
    );
  }
}

void showAboutVamos(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: VamosColors.surface,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionKicker('About Vamos', withRule: true),
          const SizedBox(height: 14),
          const Text(
            '仕事を選ぶとき、\n知りたいことは、きっと同じだ。',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.55),
          ),
          const SizedBox(height: 14),
          const Text(
            '新卒でも、転職でも、まだ進路を決めていなくても。知りたいのは、求人票に書かれた条件だけではなく、どんな人が、どんな思いで働いているのか。\n\nVamos は、学生編集部と Galaxia がつくる、働くすべての人のための Web メディアです。',
            style: TextStyle(fontSize: 14, height: 1.85, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 20),
          OutlinePillButton(
            label: 'Web 版の Vamos を見る  ↗',
            expand: true,
            onPressed: () => openExternalUrl(context, AppConfig.webUrl),
          ),
        ],
      ),
    ),
  );
}
