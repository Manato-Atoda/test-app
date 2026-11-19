import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

/// 表示中のデータの出どころ
enum DataSource {
  /// API から取得した最新データ
  live,

  /// API に接続できず、前回取得したデータを表示している
  cached,

  /// API に接続できず、前回のデータもないため、アプリに同梱したデータを表示している
  bundled,
}

/// トップ・一覧に表示するデータ一式
class Feed {
  const Feed({required this.interviews, required this.topics, required this.source, required this.updatedAt});

  final List<Interview> interviews;
  final List<Topic> topics;
  final DataSource source;

  /// データを取得した時刻（cached のときは前回取得した時刻）
  final DateTime updatedAt;

  bool get isOffline => source != DataSource.live;
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

/// アプリ全体のデータ窓口。
///
/// 一覧は「API → 前回取得したデータ → 同梱データ」の順に使う。
/// ログイン状態・保存した記事・通知の設定は端末に保存し、次回起動時に戻す。
class VamosRepository {
  VamosRepository._();

  static final instance = VamosRepository._();

  final ApiClient api = ApiClient();
  final LocalStore _store = LocalStore.instance;

  /// トップ・一覧のデータ（null は読み込み前）
  final ValueNotifier<Feed?> feed = ValueNotifier<Feed?>(null);

  /// ログイン状態（null はゲスト）
  final ValueNotifier<Session?> session = ValueNotifier<Session?>(null);

  /// 保存したインタビューの slug
  final ValueNotifier<Set<String>> saved = ValueNotifier<Set<String>>(<String>{});

  /// 通知を受け取る設定
  final ValueNotifier<bool> notificationsEnabled = ValueNotifier<bool>(false);

  Future<_Bundled>? _bundled;

  // ---------------------------------------------------------------- 起動時

  /// 端末に保存した状態を戻す。ログイン中なら会員情報を最新にする。
  Future<void> restore() async {
    saved.value = await _store.readSaved();
    notificationsEnabled.value = await _store.readNotificationsEnabled();
    final stored = await _store.readSession();
    if (stored == null) return;
    api.token = stored.token;
    session.value = stored;
    unawaited(_refreshAccount());
  }

  Future<void> _refreshAccount() async {
    try {
      final json = await api.get('/api/v1/me') as Map<String, dynamic>;
      await _setSession(session.value?.copyWith(user: UserAccount.fromJson(json)));
    } on ApiException catch (error) {
      // トークンが無効（サーバー再起動など）ならログアウト。接続できないだけならそのまま
      if (error.isUnauthorized) await _setSession(null);
    }
  }

  // ---------------------------------------------------------------- 記事

  /// 最新のデータを取得する。失敗したら前回のデータ、なければ同梱データに切り替える。
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
      unawaited(_store.writeFeed(
        interviewsJson: jsonEncode(interviews['items']),
        topicsJson: jsonEncode(topics['items']),
      ));
    } on ApiException catch (error) {
      debugPrint('API に接続できないため、保存済みのデータを表示します: $error');
      next = await _offlineFeed();
    }
    feed.value = next;
    return next;
  }

  Future<Feed> _offlineFeed() async {
    final cached = await _store.readFeed();
    if (cached != null) {
      try {
        return Feed(
          interviews: _list(jsonDecode(cached.interviewsJson), Interview.fromJson),
          topics: _list(jsonDecode(cached.topicsJson), Topic.fromJson),
          source: DataSource.cached,
          updatedAt: cached.savedAt,
        );
      } on Object catch (error) {
        debugPrint('前回のデータを読み込めませんでした: $error');
      }
    }
    final bundled = await _loadBundled();
    return Feed(
      interviews: bundled.interviews,
      topics: bundled.topics,
      source: DataSource.bundled,
      updatedAt: DateTime.now(),
    );
  }

  /// インタビューの詳細（本文つき）。保存した記事は本文も端末に残す。
  Future<Interview> interview(String slug) async {
    try {
      final json = await api.get('/api/v1/interviews/${Uri.encodeComponent(slug)}') as Map<String, dynamic>;
      if (isSaved(slug)) unawaited(_store.writeInterviewDetail(slug, jsonEncode(json)));
      return Interview.fromJson(json);
    } on ApiException catch (error) {
      if (!error.isOffline && error.statusCode != 404) rethrow;
      final stored = await _store.readInterviewDetail(slug);
      if (stored != null) return Interview.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      final bundled = await _loadBundled();
      final found = bundled.interviews.where((i) => i.slug == slug).firstOrNull;
      if (found == null) {
        throw ApiException(error.isOffline ? 'オフラインのため記事を読み込めません' : '記事が見つかりません', statusCode: 404);
      }
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
    if (next.remove(slug)) {
      unawaited(_store.removeInterviewDetail(slug));
    } else {
      next.add(slug);
      unawaited(_cacheDetail(slug));
    }
    saved.value = next;
    unawaited(_store.writeSaved(next));
  }

  Future<void> _cacheDetail(String slug) async {
    try {
      final json = await api.get('/api/v1/interviews/${Uri.encodeComponent(slug)}');
      await _store.writeInterviewDetail(slug, jsonEncode(json));
    } on ApiException {
      // オフラインなら、次に記事を開いたときに保存する
    }
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
    await _setSession(next);
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
      await _setSession(current.copyWith(user: user));
      return user;
    } on ApiException catch (error) {
      if (error.isUnauthorized) await _setSession(null);
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/api/v1/auth/logout');
    } on ApiException {
      // サーバーに届かなくても、端末側はログアウトする
    }
    await _setSession(null);
  }

  Future<void> _setSession(Session? next) async {
    api.token = next?.token;
    session.value = next;
    await _store.writeSession(next);
  }

  // ---------------------------------------------------------------- 通知

  /// 通知先の端末を登録する（ログイン中なら会員にひもづける）
  Future<void> registerDevice({required String platform, required String token}) async {
    await api.post('/api/v1/devices', {'platform': platform, 'token': token});
    notificationsEnabled.value = true;
    await _store.writeNotificationsEnabled(true);
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
