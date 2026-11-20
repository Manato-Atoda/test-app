import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// パスキー連携（ブラウザ → アプリ）で使う PKCE 用の値。
class Pkce {
  Pkce._(this.verifier, this.challenge, this.state);

  factory Pkce.generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final verifier = randomUrlSafe(48, rnd); // 64 文字
    return Pkce._(verifier, challengeFor(verifier), randomUrlSafe(16, rnd));
  }

  final String verifier;
  final String challenge;
  final String state;

  /// base64url（パディングなし）のランダム文字列。
  static String randomUrlSafe(int byteLength, [Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// S256: BASE64URL(SHA256(ASCII(code_verifier)))
  static String challengeFor(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}
