import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/vamos_theme.dart';
import 'common.dart';

/// 記事本文（ContentBlock の並び）を描画する。
class ContentBlockView extends StatelessWidget {
  const ContentBlockView(this.block, {super.key});

  final ContentBlock block;

  static const _body = TextStyle(fontSize: 15.5, height: 1.9, color: VamosColors.text);

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ParagraphBlock(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(text, style: _body),
        ),
      HeadingBlock(:final text, :final level) => _Heading(text: text, level: level),
      ImageBlock(:final src, :final caption) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 22),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(VamosRadius.large),
                child: AssetPhoto(src, fit: BoxFit.fitWidth),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, height: 1.6, color: VamosColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      SpeechBlock() => _SpeechBubble(block as SpeechBlock),
      ListBlock(:final items) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            decoration: BoxDecoration(
              color: VamosColors.surfaceMuted,
              borderRadius: BorderRadius.circular(VamosRadius.large),
            ),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5, right: 10),
                          child: Icon(Icons.check_rounded, size: 18, color: VamosColors.primary),
                        ),
                        Expanded(child: Text(item, style: _body.copyWith(fontSize: 14.5, height: 1.75))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      QuoteBlock(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: VamosColors.surface,
              border: Border(left: BorderSide(color: VamosColors.primary, width: 3)),
            ),
            child: Text(text, style: _body.copyWith(fontSize: 14.5, color: VamosColors.textMuted)),
          ),
        ),
      LinkBlock() => _LinkCard(block as LinkBlock),
      DividerBlock() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Divider(),
        ),
    };
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.level});

  final String text;
  final int level;

  @override
  Widget build(BuildContext context) {
    if (level >= 3) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.6)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(gradient: VamosColors.gradient, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(fontSize: 19.5, fontWeight: FontWeight.w800, height: 1.55)),
        ],
      ),
    );
  }
}

/// 対談の吹き出し。取材相手は左に顔写真＋水色、聞き手（学生）は右に顔写真＋グレー。
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble(this.speech);

  final SpeechBlock speech;

  @override
  Widget build(BuildContext context) {
    final answer = speech.isAnswer;
    final avatar = ClipOval(
      child: SizedBox(
        width: 42,
        height: 42,
        child: speech.avatar == null
            ? const ColoredBox(
                color: VamosColors.primaryLight,
                child: Icon(Icons.person, color: VamosColors.primary, size: 24),
              )
            : AssetPhoto(speech.avatar),
      ),
    );
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: answer ? VamosColors.primaryLight : VamosColors.surfaceMuted,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(answer ? 4 : 18),
            topRight: Radius.circular(answer ? 18 : 4),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, paragraph) in speech.paragraphs.indexed)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                child: Text(paragraph, style: const TextStyle(fontSize: 14.5, height: 1.8)),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: answer ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: answer
            ? [avatar, const SizedBox(width: 10), bubble, const SizedBox(width: 28)]
            : [const SizedBox(width: 28), bubble, const SizedBox(width: 10), avatar],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard(this.link);

  final LinkBlock link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: VamosCard(
        padding: const EdgeInsets.all(14),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('試作版では外部サイトを開けません（${link.source}）')),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: VamosColors.primaryLight,
                borderRadius: BorderRadius.circular(VamosRadius.medium),
              ),
              child: const Icon(Icons.link_rounded, color: VamosColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(link.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  if (link.description.isNotEmpty)
                    Text(
                      link.description,
                      style: const TextStyle(fontSize: 12.5, height: 1.6, color: VamosColors.textMuted),
                    ),
                  if (link.source.isNotEmpty)
                    Text(link.source, style: const TextStyle(fontSize: 11.5, color: VamosColors.textLight)),
                ],
              ),
            ),
            const Text('↗', style: TextStyle(color: VamosColors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
