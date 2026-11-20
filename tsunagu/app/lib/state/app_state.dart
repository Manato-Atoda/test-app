import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../services/passkey_flow.dart';
import '../services/secure_store.dart';

enum AppPhase { starting, loggedOut, passwordChange, guidelines, ready }

/// ログイン状態と、アプリ全体で共有する情報。
class AppState extends ChangeNotifier {
  AppState({SecureStore? store}) : _store = store ?? SecureStore() {
    api = ApiClient(baseUrl: AppConfig.defaultServerUrl);
    api.onAuthFailure = _onAuthFailure;
  }

  final SecureStore _store;
  late final ApiClient api;
  late final PasskeyFlow passkeys = PasskeyFlow(api);

  AppPhase phase = AppPhase.starting;
  Me? me;
  Company? company;
  int unreadCount = 0;

  /// ログイン画面に出すお知らせ（セッション切れなど）。
  String? loginNotice;

  /// 初回ログインの仮パスワード。再設定が終わるまでメモリにだけ置く。
  String? _tempPassword;
  bool get hasTempPassword => _tempPassword != null;

  String savedCompanyCode = '';
  String savedLoginId = '';

  String get serverUrl => api.baseUrl;
  bool get isAdmin => me?.isAdmin ?? false;

  Future<void> init() async {
    final server = await _store.readServerUrl();
    if (server != null && server.isNotEmpty) api.baseUrl = server;
    savedCompanyCode = await _store.readCompanyCode() ?? '';
    savedLoginId = await _store.readLoginId() ?? '';
    final token = await _store.readToken();
    if (token == null || token.isEmpty) {
      _setPhase(AppPhase.loggedOut);
      return;
    }
    api.token = token;
    try {
      await refreshMe();
      _route();
    } on ApiException catch (e) {
      if (e.isSessionError) {
        await _clearSession(notice: 'セッションの有効期限が切れました。もう一度ログインしてください。');
      } else if (e.isPasswordChangeRequired) {
        _setPhase(AppPhase.passwordChange);
      } else {
        // 通信できない場合はログイン画面で接続先を確認できるようにする。
        api.token = null;
        loginNotice = e.message;
        _setPhase(AppPhase.loggedOut);
      }
    }
  }

  Future<void> setServerUrl(String url) async {
    api.baseUrl = AppConfig.normalizeServerUrl(url);
    await _store.writeServerUrl(api.baseUrl);
    notifyListeners();
  }

  Future<void> resetServerUrl() async {
    api.baseUrl = AppConfig.defaultServerUrl;
    await _store.writeServerUrl(null);
    notifyListeners();
  }

  Future<void> login({
    required String companyCode,
    required String loginId,
    required String password,
  }) async {
    final code = companyCode.trim().toUpperCase();
    final id = loginId.trim();
    final result = await api.login(companyCode: code, loginId: id, password: password);
    savedCompanyCode = code;
    savedLoginId = id;
    await _store.writeLoginHints(companyCode: code, loginId: id);
    await _applyAuth(result, tempPassword: result.needsPasswordChange ? password : null);
  }

  Future<void> loginWithPasskey({required String companyCode, String? loginId}) async {
    final code = companyCode.trim().toUpperCase();
    final result = await passkeys.login(companyCode: code, loginId: loginId?.trim());
    savedCompanyCode = code;
    if (loginId != null && loginId.trim().isNotEmpty) savedLoginId = loginId.trim();
    await _store.writeLoginHints(companyCode: code, loginId: savedLoginId);
    await _applyAuth(result);
  }

  /// パスワード変更（初回の再設定・任意の変更どちらも）。
  /// [currentPassword] を省略すると、ログイン時の仮パスワードを使う。
  Future<void> changePassword({String? currentPassword, required String newPassword}) async {
    final current = currentPassword ?? _tempPassword;
    if (current == null) {
      throw const ApiException(0, 'missing_current', '現在のパスワードを入力してください。');
    }
    final result = await api.changePassword(currentPassword: current, newPassword: newPassword);
    _tempPassword = null;
    await _applyAuth(result);
  }

  Future<void> acceptGuidelines() async {
    final version = company?.guidelinesVersion ?? 0;
    me = await api.acceptGuidelines(version);
    _route();
  }

  Future<void> refreshMe() async {
    final r = await api.me();
    me = r.user;
    company = r.company;
    unreadCount = r.unread;
    notifyListeners();
  }

  void updateMe(Me user) {
    me = user;
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    if (phase != AppPhase.ready) return;
    try {
      final r = await api.me();
      me = r.user;
      company = r.company;
      if (r.unread != unreadCount ||
          r.company.guidelinesVersion > r.user.guidelinesAcceptedVersion) {
        unreadCount = r.unread;
        _route();
      }
    } on ApiException {
      // 定期更新の失敗は表示しない（セッション切れは onAuthFailure で処理される）。
    }
  }

  void setUnread(int count) {
    if (count == unreadCount) return;
    unreadCount = count;
    notifyListeners();
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      if (everywhere) {
        await api.logoutAll();
      } else {
        await api.logout();
      }
    } on ApiException {
      // サーバーに届かなくても端末からは消す。
    }
    await _clearSession(notice: everywhere ? 'すべての端末からログアウトしました。' : null);
  }

  Future<void> _applyAuth(AuthResult result, {String? tempPassword}) async {
    api.token = result.token;
    me = result.user;
    company = result.company;
    loginNotice = null;
    if (result.needsPasswordChange) {
      // 再設定用の限定トークンは保存しない（アプリを閉じたらやり直し）。
      _tempPassword = tempPassword;
      await _store.writeToken(null);
      _setPhase(AppPhase.passwordChange);
      return;
    }
    await _store.writeToken(result.token);
    try {
      final r = await api.me();
      me = r.user;
      company = r.company;
      unreadCount = r.unread;
    } on ApiException {
      // ログイン応答の情報で続ける。
    }
    _route();
  }

  void _route() {
    final user = me;
    final comp = company;
    if (user == null || comp == null) {
      _setPhase(AppPhase.loggedOut);
    } else if (user.mustChangePassword) {
      _setPhase(AppPhase.passwordChange);
    } else if (user.guidelinesAcceptedVersion < comp.guidelinesVersion) {
      _setPhase(AppPhase.guidelines);
    } else {
      _setPhase(AppPhase.ready);
    }
  }

  void _setPhase(AppPhase next) {
    phase = next;
    notifyListeners();
  }

  void _onAuthFailure(ApiException e) {
    if (e.isPasswordChangeRequired) {
      if (phase != AppPhase.passwordChange) _setPhase(AppPhase.passwordChange);
      return;
    }
    if (phase == AppPhase.loggedOut || phase == AppPhase.starting) return;
    _clearSession(notice: 'セッションの有効期限が切れました。もう一度ログインしてください。');
  }

  Future<void> _clearSession({String? notice}) async {
    api.token = null;
    me = null;
    company = null;
    unreadCount = 0;
    _tempPassword = null;
    loginNotice = notice;
    await _store.writeToken(null);
    _setPhase(AppPhase.loggedOut);
  }

  void clearNotice() {
    loginNotice = null;
  }
}
