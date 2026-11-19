import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 前回取得した一覧データ（オフライン表示用）
class CachedFeed {
  const CachedFeed({required this.interviewsJson, required this.topicsJson, required this.savedAt});

  final String interviewsJson;
  final String topicsJson;
  final DateTime savedAt;
}

/// 端末内の保存領域（shared_preferences）。
///
/// 試作のためトークンもここに保存している。本番ではトークンを Keychain / Keystore
/// （flutter_secure_storage など）に保存する。
class LocalStore {
  LocalStore._();

  static final instance = LocalStore._();

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const _sessionKey = 'session';
  static const _savedKey = 'saved_interviews';
  static const _feedInterviewsKey = 'feed_interviews';
  static const _feedTopicsKey = 'feed_topics';
  static const _feedSavedAtKey = 'feed_saved_at';
  static const _detailPrefix = 'interview_detail:';
  static const _notificationsKey = 'notifications_enabled';

  // ---------------------------------------------------------------- ログイン

  Future<Session?> readSession() async {
    final raw = await _prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Session(
        token: json['token'] as String,
        user: UserAccount.fromJson(json['user'] as Map<String, dynamic>),
      );
    } on Object {
      await _prefs.remove(_sessionKey);
      return null;
    }
  }

  Future<void> writeSession(Session? session) async {
    if (session == null) {
      await _prefs.remove(_sessionKey);
      return;
    }
    await _prefs.setString(_sessionKey, jsonEncode({'token': session.token, 'user': session.user.toJson()}));
  }

  // ---------------------------------------------------------------- 保存した記事

  Future<Set<String>> readSaved() async => (await _prefs.getStringList(_savedKey) ?? const []).toSet();

  Future<void> writeSaved(Set<String> slugs) => _prefs.setStringList(_savedKey, slugs.toList());

  /// 保存した記事の本文（オフラインでも読めるように）
  Future<String?> readInterviewDetail(String slug) => _prefs.getString('$_detailPrefix$slug');

  Future<void> writeInterviewDetail(String slug, String json) => _prefs.setString('$_detailPrefix$slug', json);

  Future<void> removeInterviewDetail(String slug) => _prefs.remove('$_detailPrefix$slug');

  // ---------------------------------------------------------------- 一覧のキャッシュ

  Future<CachedFeed?> readFeed() async {
    final interviews = await _prefs.getString(_feedInterviewsKey);
    final topics = await _prefs.getString(_feedTopicsKey);
    final savedAt = await _prefs.getInt(_feedSavedAtKey);
    if (interviews == null || topics == null || savedAt == null) return null;
    return CachedFeed(
      interviewsJson: interviews,
      topicsJson: topics,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
    );
  }

  Future<void> writeFeed({required String interviewsJson, required String topicsJson}) async {
    await _prefs.setString(_feedInterviewsKey, interviewsJson);
    await _prefs.setString(_feedTopicsKey, topicsJson);
    await _prefs.setInt(_feedSavedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ---------------------------------------------------------------- 通知

  Future<bool> readNotificationsEnabled() async => await _prefs.getBool(_notificationsKey) ?? false;

  Future<void> writeNotificationsEnabled(bool enabled) => _prefs.setBool(_notificationsKey, enabled);
}
