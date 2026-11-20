import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ログイン情報の保存先。
///
/// すべて OS の安全な保存領域（iOS/macOS: キーチェーン、Android: Keystore で暗号化、
/// Windows: 資格情報マネージャー）に置く。iCloud 等への同期や他端末への移行はさせない。
class SecureStore {
  SecureStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        // データ保護キーチェーンは署名チーム付きのエンタイトルメントが必要なため、
        // 開発中もそのまま動く従来のキーチェーンを使う。
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          usesDataProtectionKeychain: false,
        ),
      );

  final FlutterSecureStorage _storage;

  static const _kToken = 'session_token';
  static const _kServer = 'server_url';
  static const _kCompany = 'company_code';
  static const _kLoginId = 'login_id';

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // 保存できなくてもアプリは使えるようにする（次回ログインが必要になるだけ）。
    }
  }

  Future<String?> readToken() => _read(_kToken);
  Future<void> writeToken(String? token) => _write(_kToken, token);

  Future<String?> readServerUrl() => _read(_kServer);
  Future<void> writeServerUrl(String? url) => _write(_kServer, url);

  Future<String?> readCompanyCode() => _read(_kCompany);
  Future<String?> readLoginId() => _read(_kLoginId);

  Future<void> writeLoginHints({required String companyCode, required String loginId}) async {
    await _write(_kCompany, companyCode);
    await _write(_kLoginId, loginId);
  }
}
