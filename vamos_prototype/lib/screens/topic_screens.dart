import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/vamos_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/content_blocks.dart';
import '../widgets/glass.dart';
import '../widgets/list_detail.dart';
import 'search_screen.dart';

void openTopic(BuildContext context, Topic topic) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    settings: RouteSettings(name: '/topics/${topic.id}'),
    builder: (_) => TopicDetailScreen(id: topic.id, topic: topic),
  ));
}

/// トピック一覧（カテゴリーで絞り込み・引っ張って更新）。
/// 開いた iPhone Duo などの広い画面では、左に一覧・右に記事を並べる。
class TopicListScreen extends StatefulWidget {
  const TopicListScreen({super.key, required this.feed, this.active = true});

  final Feed feed;

  /// 下のタブでこの画面を表示中か
  final bool active;

  @override
  State<TopicListScreen> createState() => _TopicListScreenState();
}

class _TopicListScreenState extends State<TopicListScreen> {
  TopicCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.feed.topics;
    final topics = _filter == null ? all : all.where((t) => t.category == _filter).toList();
    return ListDetail<Topic>(
      items: topics,
      active: widget.active,
      idOf: (topic) => '${topic.id}',
      routeNameOf: (topic) => '/topics/${topic.id}',
      listBuilder: (context, selectedId, open) => _TopicList(
        feed: widget.feed,
        topics: topics,
        filter: _filter,
        onFilter: (filter) => setState(() => _filter = filter),
        selectedId: selectedId,
        onOpen: open,
      ),
      detailBuilder: (context, topic, options) => TopicDetailScreen(id: topic.id, topic: topic, paneOptions: options),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({
    required this.feed,
    required this.topics,
    required this.filter,
    required this.onFilter,
    required this.selectedId,
    required this.onOpen,
  });

  final Feed feed;
  final List<Topic> topics;
  final TopicCategory? filter;
  final ValueChanged<TopicCategory?> onFilter;
  final String? selectedId;
  final ValueChanged<Topic> onOpen;

  @override
  Widget build(BuildContext context) {
    final repository = VamosRepository.instance;
    final columns = Adaptive.columns(context);
    final rows = GridRow.chunk(topics, columns);
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
              kicker: 'Topics',
              title: 'トピック',
              description: '就活・転職にすぐ役立つノウハウと、いま知っておきたいニュース。Vamos編集部がまとめてお届けします。',
              count: topics.length,
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: Adaptive.horizontal(context).copyWith(top: 8, bottom: 8),
              child: Row(
                children: [
                  _FilterPill(label: 'すべて', selected: filter == null, onTap: () => onFilter(null)),
                  for (final category in TopicCategory.values)
                    _FilterPill(
                      label: category.label,
                      selected: filter == category,
                      onTap: () => onFilter(category),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: Adaptive.horizontal(context).copyWith(top: 12, bottom: 32),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) => GridRow(
                columns: columns,
                spacing: 14,
                children: [
                  for (final topic in rows[index])
                    TopicCard(topic: topic, selected: '${topic.id}' == selectedId, onTap: () => onOpen(topic)),
                ],
              ),
            ),
          ),
          const BottomBarSpacer(),
        ],
      ),
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

/// トピックの詳細。リンクから開いた場合は id で探す。
class TopicDetailScreen extends StatelessWidget {
  const TopicDetailScreen({
    super.key,
    required this.id,
    this.topic,
    this.paneOptions = const PaneDetailOptions(embedded: false),
  });

  final int id;
  final Topic? topic;

  /// 2 画面表示の右側に置くか、ページとして開くか
  final PaneDetailOptions paneOptions;

  @override
  Widget build(BuildContext context) {
    final known = topic;
    final embedded = paneOptions.embedded;
    return Scaffold(
      backgroundColor: VamosColors.surface,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: embedded ? null : Image.asset('assets/vamos/images/logo.png', height: 26, semanticLabel: 'VAMOS'),
        showBack: !embedded,
      ),
      body: known != null
          ? _TopicBody(topic: known, paneOptions: paneOptions)
          : FutureBuilder<Topic>(
              future: VamosRepository.instance.topic(id),
              builder: (context, snapshot) {
                if (snapshot.hasError) return ErrorView(message: snapshot.error.toString());
                final data = snapshot.data;
                if (data == null) return const Center(child: CircularProgressIndicator());
                return _TopicBody(topic: data, paneOptions: paneOptions);
              },
            ),
    );
  }
}

class _TopicBody extends StatefulWidget {
  const _TopicBody({required this.topic, required this.paneOptions});

  final Topic topic;
  final PaneDetailOptions paneOptions;

  @override
  State<_TopicBody> createState() => _TopicBodyState();
}

class _TopicBodyState extends State<_TopicBody> with PaneDetailMixin {
  @override
  PaneDetailOptions get paneOptions => widget.paneOptions;

  @override
  Widget build(BuildContext context) {
    returnToPaneIfWide();
    restoreScrollOffset();
    final topic = widget.topic;
    return ListView(
      controller: scrollController,
      padding: Adaptive.horizontal(context, maxWidth: Adaptive.readingMaxWidth)
          .copyWith(top: MediaQuery.paddingOf(context).top + 16, bottom: MediaQuery.paddingOf(context).bottom + 32),
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
    );
  }
}
