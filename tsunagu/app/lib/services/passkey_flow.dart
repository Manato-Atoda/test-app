import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../utils/pkce.dart';

/// 利用者がブラウザを閉じるなどして中断したとき。
class PasskeyCancelled implements Exception {
  const PasskeyCancelled();
}

/// パスキーはサーバーの Web ページ（WebAuthn）で扱い、結果だけをアプリに戻す。
///
/// - iOS / macOS: ASWebAuthenticationSession、Android: Auth Tab / Custom Tabs で
///   `tsunagu://auth` などのカスタム URL に戻す。
/// - Windows / Linux: 既定のブラウザで開き、`http://localhost:<port>/…` で受け取る。
class PasskeyFlow {
  PasskeyFlow(this.api);

  final ApiClient api;

  static const _landingPage = '''<!DOCTYPE html>
<html lang="ja"><head><meta charset="utf-8"><title>M</title>
<style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f4f6fb;color:#1c2333}
main{text-align:center}h1{font-size:20px}</style></head>
<body><main><h1>M に戻ります</h1><p>このタブを閉じて、アプリに戻ってください。</p></main></body></html>''';

  /// 戻り先 URL（サーバーの許可リストと一致させる）。
  static String redirectUri(String target) => AppConfig.isDesktopLoopbackAuth
      ? 'http://localhost:${AppConfig.desktopCallbackPort}/$target'
      : '${AppConfig.urlScheme}://$target';

  static String get _callbackScheme =>
      AppConfig.isDesktopLoopbackAuth ? 'http://localhost:${AppConfig.desktopCallbackPort}' : AppConfig.urlScheme;

  static const _options = FlutterWebAuth2Options(
    // Windows / Linux はアプリ内 WebView ではなく既定のブラウザを使う
    // （Windows Hello や端末のパスキーをそのまま使えるため）。
    useWebview: false,
    landingPageHtml: _landingPage,
    timeout: 300,
  );

  Future<Uri> _open(Uri url) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: _callbackScheme,
        options: _options,
      );
      return Uri.parse(result);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED' || e.code == 'canceled') throw const PasskeyCancelled();
      throw ApiException(0, 'passkey_browser', 'ブラウザを開けませんでした（${e.message ?? e.code}）。');
    }
  }

  static String _errorMessage(String error) {
    switch (error) {
      case 'cancelled':
      case 'canceled':
      case 'NotAllowedError':
        return 'パスキーの操作が取り消されたか、時間切れになりました。';
      case 'expired':
      case 'ticket_expired':
        return '有効期限が切れました。もう一度お試しください。';
      default:
        return 'パスキーでの処理に失敗しました（$error）。';
    }
  }

  /// パスキーでログインする（docs/API.md「パスキーでログイン（アプリ）」）。
  Future<AuthResult> login({required String companyCode, String? loginId}) async {
    final pkce = Pkce.generate();
    final url = Uri.parse('${api.baseUrl}/passkey/login').replace(
      queryParameters: {
        'company': companyCode,
        if (loginId != null && loginId.isNotEmpty) 'login_id': loginId,
        'redirect_uri': redirectUri('auth'),
        'code_challenge': pkce.challenge,
        'state': pkce.state,
      },
    );
    final back = await _open(url);
    final params = back.queryParameters;
    if (params['state'] != pkce.state) {
      throw const ApiException(0, 'state_mismatch', 'ログインの確認に失敗しました。もう一度お試しください。');
    }
    final error = params['error'];
    if (error != null) throw ApiException(0, 'passkey_error', _errorMessage(error));
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const ApiException(0, 'passkey_error', 'ログインの結果を受け取れませんでした。');
    }
    return api.exchangeCode(code: code, codeVerifier: pkce.verifier);
  }

  /// この端末（のブラウザ）でパスキーを登録する。
  Future<void> register({required String name}) async {
    final ticket = await api.passkeyTicket();
    final state = Pkce.randomUrlSafe(16);
    final base = Uri.parse(ticket.registerUrl);
    final url = base.replace(
      queryParameters: {...base.queryParameters, 'redirect_uri': redirectUri('passkey'), 'state': state, 'name': name},
    );
    final back = await _open(url);
    final params = back.queryParameters;
    if (params['state'] != state) {
      throw const ApiException(0, 'state_mismatch', '登録結果の確認に失敗しました。もう一度お試しください。');
    }
    final error = params['error'];
    if (error != null) throw ApiException(0, 'passkey_error', _errorMessage(error));
    if (params['status'] != 'ok') {
      throw const ApiException(0, 'passkey_error', 'パスキーを登録できませんでした。');
    }
  }
}
