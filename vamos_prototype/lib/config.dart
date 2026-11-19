import 'dart:io';

/// 接続先などの設定。
///
/// 試作ではパソコン上のモックAPI（tool/mock_api_server.py）に接続する。
/// 別の接続先を使う場合は `--dart-define=VAMOS_API=https://...` を指定する。
abstract final class AppConfig {
  static const _apiOverride = String.fromEnvironment('VAMOS_API');

  /// API の接続先。Android エミュレーターからはホストの localhost が 10.0.2.2 になる。
  static String get apiBaseUrl {
    if (_apiOverride.isNotEmpty) return _apiOverride;
    return Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://localhost:8787';
  }

  /// 管理画面（通知の配信テスト）の URL
  static String get adminUrl => '$apiBaseUrl/admin';

  /// Web 版のトップページ
  static const webUrl = 'https://webmagazine-vamos.com/';

  /// 共有するときの記事の URL。
  /// 試作では Web 版の記事 URL が未確定のため、トップページを使う（本番の URL が決まったら差し替える）。
  static String shareUrl(String slug) => webUrl;

  /// アプリ内リンクのスキーム（vamos://app/interviews/<slug>）
  static const linkScheme = 'vamos';
}
