import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'models.dart';

/// API のエラー。`message` はサーバーが返す日本語の説明。
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.extra = const {}]);

  final int status;
  final String code;
  final String message;
  final Json extra;

  /// セッション切れなど、ログイン画面へ戻すべきエラーか。
  bool get isSessionError =>
      status == 401 &&
      code != 'invalid_credentials' &&
      code != 'invalid_current_password';

  bool get isPasswordChangeRequired =>
      status == 403 && code == 'password_change_required';

  /// パスワード規則違反の詳細（400 password_policy）。
  List<String> get details {
    final d = extra['details'];
    return d is List ? d.map((e) => '$e').toList() : const [];
  }

  @override
  String toString() => message;
}

typedef AuthFailureHandler = void Function(ApiException e);

/// つなぐ API の薄いクライアント。
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
    : _http = client ?? http.Client();

  String baseUrl;
  String? token;

  /// 401（セッション切れ）・403 password_change_required を受けたときに呼ばれる。
  AuthFailureHandler? onAuthFailure;

  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<Json> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    bool auth = true,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (auth && token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      // bodyBytes を設定すると Content-Length が付く（チャンク転送にしない）。
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'timeout', 'サーバーの応答がありません。しばらくしてからもう一度お試しください。');
    } catch (_) {
      throw const ApiException(0, 'network', 'サーバーに接続できませんでした。ネットワークと接続先を確認してください。');
    }

    Json decoded = const {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final v = jsonDecode(utf8.decode(response.bodyBytes));
        if (v is Map) decoded = v.cast<String, dynamic>();
      } catch (_) {
        if (response.statusCode < 400) {
          throw ApiException(response.statusCode, 'bad_response', 'サーバーから想定外の応答がありました。');
        }
      }
    }

    if (response.statusCode >= 400) {
      final err = decoded['error'];
      final errMap = err is Map ? err.cast<String, dynamic>() : const <String, dynamic>{};
      final e = ApiException(
        response.statusCode,
        (errMap['code'] as String?) ?? 'http_${response.statusCode}',
        (errMap['message'] as String?) ?? _fallbackMessage(response.statusCode),
        errMap,
      );
      if (auth && token != null && (e.isSessionError || e.isPasswordChangeRequired)) {
        onAuthFailure?.call(e);
      }
      throw e;
    }
    return decoded;
  }

  static String _fallbackMessage(int status) {
    if (status == 401) return 'ログインが必要です。';
    if (status == 403) return 'この操作を行う権限がありません。';
    if (status == 404) return '見つかりませんでした。削除された可能性があります。';
    if (status == 429) return '操作が多すぎます。しばらくしてからもう一度お試しください。';
    if (status >= 500) return 'サーバーでエラーが発生しました。';
    return 'エラーが発生しました（$status）。';
  }

  Map<String, String> get _device => {
    'platform': AppConfig.platformId,
    'name': AppConfig.deviceLabel,
  };

  // ---- 公開・認証 ----

  Future<PasswordPolicy> meta() async {
    final j = await _send('GET', '/api/meta', auth: false);
    return PasswordPolicy.fromJson((j['password_policy'] as Map?)?.cast<String, dynamic>() ?? const {});
  }

  Future<AuthResult> login({
    required String companyCode,
    required String loginId,
    required String password,
  }) async {
    final j = await _send('POST', '/api/auth/login', auth: false, body: {
      'company_code': companyCode,
      'login_id': loginId,
      'password': password,
      'device': _device,
    });
    return AuthResult.fromJson(j);
  }

  Future<PasswordPolicy> passwordPolicy() async =>
      PasswordPolicy.fromJson(await _send('GET', '/api/auth/password-policy'));

  Future<AuthResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final j = await _send('POST', '/api/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    return AuthResult.fromJson(j);
  }

  Future<AuthResult> exchangeCode({
    required String code,
    required String codeVerifier,
  }) async {
    final j = await _send('POST', '/api/auth/exchange', auth: false, body: {
      'code': code,
      'code_verifier': codeVerifier,
      'device': _device,
    });
    return AuthResult.fromJson(j);
  }

  Future<void> logout() => _send('POST', '/api/auth/logout');

  Future<void> logoutAll() => _send('POST', '/api/auth/logout-all');

  // ---- 自分 ----

  Future<({Me user, Company company, int unread})> me() async {
    final j = await _send('GET', '/api/me');
    return (
      user: Me.fromJson((j['user'] as Map).cast<String, dynamic>()),
      company: Company.fromJson((j['company'] as Map).cast<String, dynamic>()),
      unread: (j['unread_notifications'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Me> updateBio(String bio) async {
    final j = await _send('PATCH', '/api/me', body: {'bio': bio});
    return Me.fromJson((j['user'] as Map).cast<String, dynamic>());
  }

  Future<Me> acceptGuidelines(int version) async {
    final j = await _send('POST', '/api/me/accept-guidelines', body: {'version': version});
    return Me.fromJson((j['user'] as Map).cast<String, dynamic>());
  }

  Future<List<SessionInfo>> sessions() async {
    final j = await _send('GET', '/api/me/sessions');
    return ((j['sessions'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => SessionInfo.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> deleteSession(int id) => _send('DELETE', '/api/me/sessions/$id');

  Future<List<Passkey>> passkeys() async {
    final j = await _send('GET', '/api/me/passkeys');
    return ((j['passkeys'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Passkey.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> deletePasskey(int id) => _send('DELETE', '/api/me/passkeys/$id');

  Future<PasskeyTicket> passkeyTicket() async =>
      PasskeyTicket.fromJson(await _send('POST', '/api/me/passkeys/ticket'));

  // ---- SNS ----

  Future<List<Channel>> channels() async {
    final j = await _send('GET', '/api/channels');
    return ((j['channels'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Channel.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Channel> channel(int id) async {
    final j = await _send('GET', '/api/channels/$id');
    return Channel.fromJson((j['channel'] as Map).cast<String, dynamic>());
  }

  Future<Channel> joinChannel(int id) async {
    final j = await _send('POST', '/api/channels/$id/join');
    return Channel.fromJson((j['channel'] as Map).cast<String, dynamic>());
  }

  Future<Channel> leaveChannel(int id) async {
    final j = await _send('POST', '/api/channels/$id/leave');
    return Channel.fromJson((j['channel'] as Map).cast<String, dynamic>());
  }

  Future<FeedPage> feed({int? channelId, String? kind, int? before, int limit = 20}) async {
    final j = await _send('GET', '/api/feed', query: {
      'channel_id': channelId,
      'kind': kind,
      'before': before,
      'limit': limit,
    });
    return FeedPage.fromJson(j);
  }

  Post _post(Json j) => Post.fromJson((j['post'] as Map).cast<String, dynamic>());

  Future<Post> createPost({
    required int channelId,
    required String body,
    bool announcement = false,
    bool requireAck = false,
  }) async {
    final j = await _send('POST', '/api/posts', body: {
      'channel_id': channelId,
      'body': body,
      'kind': announcement ? 'announcement' : 'post',
      'require_ack': announcement && requireAck,
    });
    return _post(j);
  }

  Future<PostDetail> post(int id) async => PostDetail.fromJson(await _send('GET', '/api/posts/$id'));

  Future<Post> editPost(int id, String body) async =>
      _post(await _send('PATCH', '/api/posts/$id', body: {'body': body}));

  Future<void> deletePost(int id) => _send('DELETE', '/api/posts/$id');

  Future<Comment> addComment(int postId, String body) async {
    final j = await _send('POST', '/api/posts/$postId/comments', body: {'body': body});
    return Comment.fromJson((j['comment'] as Map).cast<String, dynamic>());
  }

  Future<void> deleteComment(int id) => _send('DELETE', '/api/comments/$id');

  Future<Post> setReaction(int postId, String key, bool on) async =>
      _post(await _send(on ? 'PUT' : 'DELETE', '/api/posts/$postId/reactions/$key'));

  Future<Post> acknowledge(int postId) async => _post(await _send('POST', '/api/posts/$postId/ack'));

  Future<AckStatus> acks(int postId) async => AckStatus.fromJson(await _send('GET', '/api/posts/$postId/acks'));

  Future<void> report({
    required String targetType,
    required int targetId,
    required String reason,
  }) => _send('POST', '/api/reports', body: {
    'target_type': targetType,
    'target_id': targetId,
    'reason': reason,
  });

  Future<NotificationPage> notifications({int? before}) async =>
      NotificationPage.fromJson(await _send('GET', '/api/notifications', query: {'before': before}));

  Future<void> readAllNotifications() => _send('POST', '/api/notifications/read-all');

  Future<void> readNotification(int id) => _send('POST', '/api/notifications/$id/read');

  Future<List<UserSummary>> directory({String? q}) async {
    final j = await _send('GET', '/api/directory', query: {'q': q});
    return ((j['users'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => UserSummary.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<UserProfile> user(int id) async => UserProfile.fromJson(await _send('GET', '/api/users/$id'));

  Future<List<Post>> search(String q) async {
    final j = await _send('GET', '/api/search', query: {'q': q});
    return ((j['posts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Post.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}
