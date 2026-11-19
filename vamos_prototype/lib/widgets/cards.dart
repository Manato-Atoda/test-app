import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/vamos_theme.dart';
import 'common.dart';

/// インタビューのカード（画像・ラベル・タイトル・抜粋・著者）。
class InterviewCard extends StatelessWidget {
  const InterviewCard({super.key, required this.interview, required this.onTap});

  final Interview interview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VamosCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: AssetPhoto(interview.thumbnail)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CategoryChip('インタビュー'),
                const SizedBox(height: 10),
                Text(
                  interview.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.55),
                ),
                if (interview.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    interview.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, height: 1.7, color: VamosColors.textMuted),
                  ),
                ],
                const SizedBox(height: 12),
                AuthorLine(author: interview.author, date: interview.date),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// トピックのカード（カテゴリー・タイトル・抜粋・日付）。
class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VamosCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topic.category != null) CategoryChip(topic.category!.label),
          const SizedBox(height: 10),
          Text(topic.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.55)),
          if (topic.excerpt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              topic.excerpt,
              style: const TextStyle(fontSize: 12.5, height: 1.7, color: VamosColors.textMuted),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${topic.date}  ・  ${topic.author}',
            style: const TextStyle(fontSize: 12, color: VamosColors.textLight),
          ),
        ],
      ),
    );
  }
}

/// トップページ用のトピック行（枠線つきラベル＋タイトル）。
class TopicRow extends StatelessWidget {
  const TopicRow({super.key, required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VamosColors.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (topic.category != null) CategoryChip(topic.category!.label, style: ChipStyle.outline),
                const Spacer(),
                const Text('読む', style: TextStyle(fontSize: 12, color: VamosColors.textLight)),
              ],
            ),
            const SizedBox(height: 8),
            Text(topic.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.6)),
          ],
        ),
      ),
    );
  }
}
