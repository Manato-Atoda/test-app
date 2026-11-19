import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'models.dart';

/// 表示中のデータの出どころ
enum DataSource {
  /// API から取得した最新データ
  live,

  /// API に接続できず、アプリに同梱したデータを表示している
  bundled,
}

/// トップ・一覧に表示するデータ一式
class Feed {
  const Feed({required this.interviews, required this.topics, required this.source, required this.updatedAt});

  final List<Interview> interviews;
  final List<Topic> topics;
  final DataSource source;
  final DateTime updatedAt;

  bool get isOffline => source == DataSource.bundled;
}

/// 検索結果（インタビューまたはトピック）
sealed class SearchHit {
  const SearchHit();
}

final class InterviewHit extends SearchHit {
  const InterviewHit(this.interview);
  final Interview interview;
}

final class TopicHit extends SearchHit {
  const TopicHit(this.topic);
  final Topic topic;
}

/// アプリ全体のデータ窓口。API を優先し、つながらない場合は同梱データで表示する。
class VamosRepository {
  VamosRepository._();

  static final instance = VamosRepository._();

  final ApiClient api = ApiClient();

  /// トップ・一覧のデータ（null は読み込み前）
  final ValueNotifier<Feed?> feed = ValueNotifier<Feed?>(null);

  /// ログイン状態（null はゲスト）
  final ValueNotifier<Session?> session = ValueNotifier<Session?>(null);

  /// 保存したインタビューの slug
  final ValueNotifier<Set<String>> saved = ValueNotifier<Set<String>>(<String>{});

  /// 通知を受け取る設定
  final ValueNotifier<bool> notificationsEnabled = ValueNotifier<bool>(false);

  Future<_Bundled>? _bundled;

  // ---------------------------------------------------------------- 記事

  /// 最新のデータを取得する。失敗したら同梱データに切り替える。
  Future<Feed> refresh() async {
    Feed next;
    try {
      final interviews = await api.get('/api/v1/interviews') as Map<String, dynamic>;
      final topics = await api.get('/api/v1/topics') as Map<String, dynamic>;
      next = Feed(
        interviews: _list(interviews['items'], Interview.fromJson),
        topics: _list(topics['items'], Topic.fromJson),
        source: DataSource.live,
        updatedAt: DateTime.now(),
      );
    } on ApiException catch (error) {
      debugPrint('API に接続できないため同梱データを表示します: $error');
      final bundled = await _loadBundled();
      next = Feed(
        interviews: bundled.interviews,
        topics: bundled.topics,
        source: DataSource.bundled,
        updatedAt: DateTime.now(),
      );
    }
    feed.value = next;
    return next;
  }

  /// インタビューの詳細（本文つき）
  Future<Interview> interview(String slug) async {
    try {
      final json = await api.get('/api/v1/interviews/${Uri.encodeComponent(slug)}') as Map<String, dynamic>;
      return Interview.fromJson(json);
    } on ApiException catch (error) {
      if (!error.isOffline && error.statusCode != 404) rethrow;
      final bundled = await _loadBundled();
      final found = bundled.interviews.where((i) => i.slug == slug).firstOrNull;
      if (found == null) throw const ApiException('記事が見つかりません', statusCode: 404);
      return found;
    }
  }

  /// トピック（表示中のデータ→同梱データの順に探す）
  Future<Topic> topic(int id) async {
    final current = feed.value?.topics.where((t) => t.id == id).firstOrNull;
    if (current != null) return current;
    final bundled = await _loadBundled();
    final found = bundled.topics.where((t) => t.id == id).firstOrNull;
    if (found == null) throw const ApiException('トピックが見つかりません', statusCode: 404);
    return found;
  }

  /// タイトル・抜粋・会社名・リードからキーワード検索する（表示中のデータが対象）
  List<SearchHit> search(String keyword) {
    final words = keyword.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final data = feed.value;
    if (words.isEmpty || data == null) return const [];
    bool matches(List<String> fields) {
      final text = fields.join(' ').toLowerCase();
      return words.every(text.contains);
    }

    return [
      for (final i in data.interviews)
        if (matches([i.title, i.excerpt, i.company])) InterviewHit(i),
      for (final t in data.topics)
        if (matches([t.title, t.excerpt, t.lead, t.category?.label ?? ''])) TopicHit(t),
    ];
  }

  // ---------------------------------------------------------------- 保存

  bool isSaved(String slug) => saved.value.contains(slug);

  void toggleSaved(String slug) {
    final next = Set<String>.of(saved.value);
    if (!next.remove(slug)) next.add(slug);
    saved.value = next;
  }

  // ---------------------------------------------------------------- 会員

  /// 確認コードをメールで送る。試作のモックAPIはコードを応答にも含めて返す。
  Future<String?> requestCode(String email) async {
    final json = await api.post('/api/v1/auth/code', {'email': email}) as Map<String, dynamic>;
    return json['debugCode'] as String?;
  }

  Future<Session> verify(String email, String code) async {
    final json = await api.post('/api/v1/auth/verify', {'email': email, 'code': code}) as Map<String, dynamic>;
    final next = Session(
      token: json['token'] as String,
      user: UserAccount.fromJson(json['user'] as Map<String, dynamic>),
    );
    api.token = next.token;
    session.value = next;
    return next;
  }

  Future<UserAccount> updateProfile({
    required String displayName,
    required List<String> statuses,
    required List<String> interests,
    required List<String> areas,
  }) async {
    final current = session.value;
    if (current == null) throw const ApiException('ログインしてください', statusCode: 401);
    try {
      final json = await api.put('/api/v1/me', {
        'displayName': displayName,
        'statuses': statuses,
        'interests': interests,
        'areas': areas,
      }) as Map<String, dynamic>;
      final user = UserAccount.fromJson(json);
      session.value = current.copyWith(user: user);
      return user;
    } on ApiException catch (error) {
      if (error.isUnauthorized) _clearSession();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/api/v1/auth/logout');
    } on ApiException {
      // サーバーに届かなくても、端末側はログアウトする
    }
    _clearSession();
  }

  void _clearSession() {
    api.token = null;
    session.value = null;
  }

  // ---------------------------------------------------------------- 通知

  /// 通知先の端末を登録する（ログイン中なら会員にひもづける）
  Future<void> registerDevice({required String platform, required String token}) async {
    await api.post('/api/v1/devices', {'platform': platform, 'token': token});
  }

  // ---------------------------------------------------------------- 同梱データ

  Future<_Bundled> _loadBundled() => _bundled ??= _Bundled.load();

  static List<T> _list<T>(Object? json, T Function(Map<String, dynamic>) parse) =>
      ((json as List?) ?? const []).map((e) => parse(e as Map<String, dynamic>)).toList();
}

class _Bundled {
  const _Bundled(this.interviews, this.topics);

  final List<Interview> interviews;
  final List<Topic> topics;

  static Future<_Bundled> load() async {
    final interviews = await rootBundle.loadString('assets/vamos/data/interviews.json');
    final topics = await rootBundle.loadString('assets/vamos/data/topics.json');
    return _Bundled(
      VamosRepository._list(jsonDecode(interviews), Interview.fromJson),
      VamosRepository._list(jsonDecode(topics), Topic.fromJson),
    );
  }
}
