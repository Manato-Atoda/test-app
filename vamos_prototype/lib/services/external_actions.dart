import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';

/// 外部サイトをアプリ内ブラウザ（iOS は Safari ビュー）で開く。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  final opened = uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text('ページを開けませんでした（$url）')));
  }
}

/// インタビューを共有する（LINE・X・メールなど、端末の共有シートを使う）。
Future<void> shareInterview(BuildContext context, Interview interview) async {
  // iPad では共有シートの表示位置が必要
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  await SharePlus.instance.share(ShareParams(
    subject: interview.title,
    text: '${interview.title}｜Vamos\n${AppConfig.shareUrl(interview.slug)}',
    sharePositionOrigin: origin,
  ));
}
