import 'package:material_ui/material_ui.dart';

import '../state/app_scope.dart';
import '../theme.dart';

/// サーバーの画像（/api/uploads/...）。社内の画像なので、ログインのトークンを付けて読み込む。
class AuthImage extends StatelessWidget {
  const AuthImage(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height});

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.read(context).api;
    final p = context.m;
    return Image.network(
      api.absoluteUrl(url),
      headers: api.imageHeaders,
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(width: width, height: height, color: p.borderSoft),
      errorBuilder: (context, error, stack) => Container(
        width: width,
        height: height,
        color: p.borderSoft,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: p.muted),
      ),
    );
  }
}
