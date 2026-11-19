import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/vamos_theme.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/content_blocks.dart';

void openTopic(BuildContext context, Topic topic) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TopicDetailScreen(topic: topic)));
}

/// トピック一覧（カテゴリーで絞り込み）
class TopicListScreen extends StatefulWidget {
  const TopicListScreen({super.key, required this.topics});

  final List<Topic> topics;

  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  TopicCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final topics = _filter == null ? widget.topics : widget.topics.where((t) => t.category == _filter).toList();
    return CustomScrollView(
      slivers: [
        const VamosSliverAppBar(),
        SliverToBoxAdapter(
          child: PageIntro(
            kicker: 'Topics',
            title: 'トピック',
            description: '就活・転職にすぐ役立つノウハウと、いま知っておきたいニュース。Vamos編集部がまとめてお届けします。',
            count: topics.length,
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                _FilterPill(label: 'すべて', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                for (final category in TopicCategory.values)
                  _FilterPill(
                    label: category.label,
                    selected: _filter == category,
                    onTap: () => setState(() => _filter = category),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          sliver: SliverList.separated(
            itemCount: topics.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) =>
                TopicCard(topic: topics[index], onTap: () => openTopic(context, topics[index])),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? VamosColors.buttonGradient : null,
            color: selected ? null : VamosColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.transparent : VamosColors.border),
            boxShadow: selected ? VamosShadows.glow : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : VamosColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// トピックの詳細
class TopicDetailScreen extends StatelessWidget {
  const TopicDetailScreen({super.key, required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VamosColors.surface,
      appBar: AppBar(title: Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [
          if (topic.category != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CategoryChip(topic.category!.label, style: ChipStyle.filled),
            ),
          const SizedBox(height: 14),
          Text(topic.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.5)),
          const SizedBox(height: 10),
          Text(
            '${topic.date}  ・  ${topic.author}',
            style: const TextStyle(fontSize: 12.5, color: VamosColors.textLight),
          ),
          if (topic.lead.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VamosColors.primaryLight,
                borderRadius: BorderRadius.circular(VamosRadius.large),
              ),
              child: Text(topic.lead, style: const TextStyle(fontSize: 14.5, height: 1.85)),
            ),
          ],
          const SizedBox(height: 22),
          for (final block in topic.blocks) ContentBlockView(block),
          if (topic.blocks.isEmpty)
            const Text(
              '本文は Web 版で公開しています（試作版では要約のみ表示）。',
              style: TextStyle(fontSize: 13, color: VamosColors.textMuted),
            ),
        ],
      ),
    );
  }
}
