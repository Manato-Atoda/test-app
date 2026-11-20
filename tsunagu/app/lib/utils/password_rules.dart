import '../api/models.dart';

class PasswordCheck {
  const PasswordCheck(this.label, this.ok);

  final String label;
  final bool ok;
}

final _letter = RegExp(r'[A-Za-z]');
final _digit = RegExp(r'[0-9]');
final _alnum = RegExp(r'^[A-Za-z0-9]$');

/// 画面に出すパスワード規則のチェック結果（最終判定はサーバーが行う）。
///
/// 社員コードを含まない・直近と同じでない、などはサーバー側でのみ確認する。
List<PasswordCheck> evaluatePassword(
  String password,
  String confirm,
  PasswordPolicy policy,
) {
  final chars = password.split('');
  final hasSymbol = chars.any((c) => policy.allowedSymbols.contains(c));
  final allAllowed = chars.every(
    (c) => _alnum.hasMatch(c) || policy.allowedSymbols.contains(c),
  );
  final length = password.length;
  return [
    PasswordCheck(
      '${policy.minLength}文字以上（${policy.maxLength}文字まで）',
      length >= policy.minLength && length <= policy.maxLength,
    ),
    if (policy.requireLetter) PasswordCheck('英字（a〜z・A〜Z）を含む', _letter.hasMatch(password)),
    if (policy.requireDigit) PasswordCheck('数字（0〜9）を含む', _digit.hasMatch(password)),
    if (policy.requireSymbol) PasswordCheck('記号を含む', hasSymbol),
    PasswordCheck('使えない文字（空白・全角文字など）を含まない', password.isNotEmpty && allAllowed),
    PasswordCheck('確認用と一致している', password.isNotEmpty && password == confirm),
  ];
}

bool passwordAcceptable(String password, String confirm, PasswordPolicy policy) =>
    evaluatePassword(password, confirm, policy).every((c) => c.ok);
