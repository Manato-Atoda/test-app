import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/body_parser.dart';
import 'common.dart';

/// 投稿本文。URL はタップで（確認のうえ）ブラウザで開き、@社員コード は強調する。
class RichBody extends StatefulWidget {
  const RichBody(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await confirmDialog(
      context,
      title: '外部のページを開きます',
      message: '$url\n\n社外のサイトの場合、社内の情報を入力しないよう注意してください。',
      confirmLabel: '開く',
    );
    if (!ok) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showInfo(context, 'ページを開けませんでした。');
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyLarge;
    final spans = <InlineSpan>[];
    for (final seg in parseBody(widget.text)) {
      switch (seg.type) {
        case BodySegmentType.text:
          spans.add(TextSpan(text: seg.text));
        case BodySegmentType.url:
          final r = TapGestureRecognizer()..onTap = () => _openUrl(seg.text);
          _recognizers.add(r);
          spans.add(
            TextSpan(
              text: seg.text,
              style: TextStyle(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: r,
            ),
          );
        case BodySegmentType.mention:
          spans.add(
            TextSpan(
              text: seg.text,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
      }
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
