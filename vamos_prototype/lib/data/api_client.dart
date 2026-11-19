import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';

/// API 呼び出しの失敗。statusCode が null のときは接続そのものができていない。
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isOffline => statusCode == null;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// VAMOS API の最小限のクライアント（dart:io のみで実装）。
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final String baseUrl;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  /// ログイン中のトークン（Authorization: Bearer）
  String? token;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, [Map<String, Object?>? body]) => _send('POST', path, body);

  Future<dynamic> put(String path, Map<String, Object?> body) => _send('PUT', path, body);

  Future<dynamic> _send(String method, String path, [Map<String, Object?>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final request = await _http.openUrl(method, uri).timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final bearer = token;
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        // 分割送信（chunked）ではなく長さを明示する（PHP・簡易サーバーでも確実に読めるように）
        request.contentLength = bytes.length;
        request.add(bytes);
      } else if (method != 'GET') {
        request.contentLength = 0;
      }
      final response = await request.close().timeout(const Duration(seconds: 10));
      final text = await response.transform(utf8.decoder).join();
      final data = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode >= 400) {
        final message = data is Map && data['error'] is String ? data['error'] as String : '通信エラー（${response.statusCode}）';
        throw ApiException(message, statusCode: response.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException('サーバーに接続できません');
    } on TimeoutException {
      throw const ApiException('サーバーの応答がありません');
    } on HttpException {
      throw const ApiException('サーバーに接続できません');
    } on FormatException {
      throw const ApiException('サーバーの応答を読み取れません', statusCode: 500);
    }
  }
}
