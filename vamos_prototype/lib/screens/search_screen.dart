import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme/vamos_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'interview_screens.dart';
import 'topic_screens.dart';

/// ヘッダー右上の検索ボタン
class SearchButton extends StatelessWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GlassIconButton(
        symbol: 'magnifyingglass',
        icon: Icons.search_rounded,
        tooltip: '検索',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/search'),
          builder: (_) => const SearchScreen(),
        )),
      ),
    );
  }
}

/// インタビューとトピックのキーワード検索
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialKeyword = ''});

  final String initialKeyword;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _suggestions = ['北九州', 'IT', '社長', '面接', '転職', '就活'];

  late final _controller = TextEditingController(text: widget.initialKeyword);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setKeyword(String keyword) {
    _controller
      ..text = keyword
      ..selection = TextSelection.collapsed(offset: keyword.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _controller.text;
    final hits = VamosRepository.instance.search(keyword);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: widget.initialKeyword.isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '企業名・キーワードで検索',
            border: InputBorder.none,
            suffixIcon: keyword.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _setKeyword('')),
          ),
        ),
      ),
      body: keyword.trim().isEmpty
          ? _Suggestions(suggestions: _suggestions, onSelect: _setKeyword)
          : hits.isEmpty
              ? const ErrorView(message: '見つかりませんでした。別のキーワードで試してください。')
              : ListView.separated(
                  padding: Adaptive.horizontal(context, maxWidth: Adaptive.readingMaxWidth)
                      .copyWith(top: 16, bottom: MediaQuery.paddingOf(context).bottom + 16),
                  itemCount: hits.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Text(
                        '「$keyword」の検索結果 ${hits.length} 件',
                        style: const TextStyle(fontSize: 13, color: VamosColors.textMuted),
                      );
                    }
                    return _HitTile(hit: hits[index - 1]);
                  },
                ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onSelect});

  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: Adaptive.horizontal(context, maxWidth: Adaptive.readingMaxWidth).copyWith(top: 20, bottom: 20),
      children: [
        const SectionKicker('Keywords'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in suggestions)
              ActionChip(
                label: Text(word),
                onPressed: () => onSelect(word),
                backgroundColor: VamosColors.surface,
                side: const BorderSide(color: VamosColors.border),
                shape: const StadiumBorder(),
              ),
          ],
        ),
      ],
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final (label, title, subtitle, thumbnail, onTap) = switch (hit) {
      InterviewHit(:final interview) => (
          'インタビュー',
          interview.title,
          interview.date,
          interview.thumbnail,
          () => openInterview(context, interview),
        ),
      TopicHit(:final topic) => (
          topic.category?.label ?? 'トピック',
          topic.title,
          topic.date,
          null,
          () => openTopic(context, topic),
        ),
    };
    return VamosCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (thumbnail != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(VamosRadius.medium),
              child: SizedBox(width: 88, height: 50, child: AssetPhoto(thumbnail)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CategoryChip(label),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.5),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: VamosColors.textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
