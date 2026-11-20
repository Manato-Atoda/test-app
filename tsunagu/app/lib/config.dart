import 'package:flutter/foundation.dart';

/// アプリ全体の設定値。
class AppConfig {
  AppConfig._();

  static const appName = 'M';

  /// `--dart-define=TSUNAGU_API=https://sns.example.co.jp` で接続先を固定できる。
  static const _definedServer = String.fromEnvironment('TSUNAGU_API');

  /// パスキー連携で使うカスタム URL スキーム（サーバー側の許可リストと一致させる）。
  static const urlScheme = 'tsunagu';

  /// Windows / Linux でパスキー連携の戻り先を受けるローカルポート。
  static const desktopCallbackPort = 43823;

  /// 既定の接続先。Android エミュレーターからホスト PC は 10.0.2.2 で見える。
  static String get defaultServerUrl {
    if (_definedServer.isNotEmpty) return normalizeServerUrl(_definedServer);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8790';
    }
    return 'http://localhost:8790';
  }

  /// 末尾のスラッシュを取り、スキームが無ければ https を補う。
  static String normalizeServerUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// ログイン時にサーバーへ送る端末の種類。
  static String get platformId {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'other';
    }
  }

  /// セッション一覧やパスキー名に使う端末の表示名（個人情報は含めない）。
  static String get deviceLabel {
    switch (platformId) {
      case 'ios':
        return 'iPhone / iPad';
      case 'android':
        return 'Android';
      case 'macos':
        return 'Mac';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return 'その他の端末';
    }
  }

  static bool get isDesktopLoopbackAuth =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux);
}
