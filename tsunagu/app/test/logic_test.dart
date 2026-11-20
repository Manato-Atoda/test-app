import 'package:flutter_test/flutter_test.dart';
import 'package:tsunagu/api/api_client.dart';
import 'package:tsunagu/api/models.dart';
import 'package:tsunagu/config.dart';
import 'package:tsunagu/utils/body_parser.dart';
import 'package:tsunagu/utils/format.dart';
import 'package:tsunagu/utils/password_rules.dart';
import 'package:tsunagu/utils/pkce.dart';

void main() {
  group('パスワード規則', () {
    const policy = PasswordPolicy();

    bool ok(String pw) => passwordAcceptable(pw, pw, policy);

    test('8文字以上・英字と数字を含めば OK、記号も使える', () {
      expect(ok('abcd1234'), isTrue);
      expect(ok('Abcd-1234!'), isTrue);
    });

    test('短い・英字なし・数字なしは NG', () {
      expect(ok('abc123'), isFalse);
      expect(ok('12345678'), isFalse);
      expect(ok('abcdefgh'), isFalse);
    });

    test('空白・全角は NG', () {
      expect(ok('abcd 1234'), isFalse);
      expect(ok('abcd１２３４5'), isFalse);
      expect(ok('パスワード1234ab'), isFalse);
    });

    test('確認用と一致しないと NG', () {
      expect(passwordAcceptable('abcd1234', 'abcd1235', policy), isFalse);
    });

    test('記号必須の設定', () {
      const strict = PasswordPolicy(requireSymbol: true, minLength: 10);
      expect(passwordAcceptable('abcd123456', 'abcd123456', strict), isFalse);
      expect(passwordAcceptable('abcd12345#', 'abcd12345#', strict), isTrue);
      expect(passwordAcceptable('ab12#', 'ab12#', strict), isFalse);
    });

    test('チェック項目は規則に合わせて増減する', () {
      expect(evaluatePassword('', '', policy).length, 5);
      expect(evaluatePassword('', '', const PasswordPolicy(requireSymbol: true)).length, 6);
    });
  });

  group('PKCE', () {
    test('RFC 7636 の例と一致する', () {
      expect(
        Pkce.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifier は 43〜128 文字の URL 安全な文字列', () {
      final p = Pkce.generate();
      expect(p.verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(p.verifier), isTrue);
      expect(p.challenge, Pkce.challengeFor(p.verifier));
      expect(p.state, isNotEmpty);
    });
  });

  group('本文の解析', () {
    test('URL とメンションを分ける', () {
      final segs = parseBody('資料は https://example.com/a?b=1 です。@E0001 さん確認を');
      expect(segs, [
        const BodySegment(BodySegmentType.text, '資料は '),
        const BodySegment(BodySegmentType.url, 'https://example.com/a?b=1'),
        const BodySegment(BodySegmentType.text, ' です。'),
        const BodySegment(BodySegmentType.mention, '@E0001'),
        const BodySegment(BodySegmentType.text, ' さん確認を'),
      ]);
    });

    test('メールアドレスはメンションにしない・文末の句点は URL に含めない', () {
      final segs = parseBody('連絡先 taro@example.com まで。https://example.com.');
      expect(segs.where((s) => s.type == BodySegmentType.mention), isEmpty);
      expect(segs.firstWhere((s) => s.type == BodySegmentType.url).text, 'https://example.com');
      expect(segs.map((s) => s.text).join(), '連絡先 taro@example.com まで。https://example.com.');
    });
  });

  group('相対時刻', () {
    final now = DateTime(2026, 11, 20, 15, 0);
    test('分・時間・昨日・日付', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 10)), now: now), 'たった今');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5分前');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3時間前');
      expect(relativeTime(DateTime(2026, 11, 19, 9, 5), now: now), '昨日 9:05');
      expect(relativeTime(DateTime(2026, 10, 1, 18, 30), now: now), '10月1日 18:30');
      expect(relativeTime(DateTime(2025, 1, 2), now: now), '2025年1月2日');
    });
  });

  group('モデル', () {
    test('Post を API の形から読み込む', () {
      final post = Post.fromJson({
        'id': 10,
        'channel': {'id': 1, 'name': '全社'},
        'author': {
          'id': 3,
          'display_name': '山田 花子',
          'employee_code': 'E0003',
          'department': '営業部',
          'title': '主任',
          'avatar_color': 4,
          'role': 'member',
          'status': 'active',
        },
        'body': 'こんにちは',
        'kind': 'announcement',
        'require_ack': true,
        'acked_by_me': false,
        'ack_count': 2,
        'like_count': 2,
        'liked_by_me': true,
        'identity': 'real',
        'images': [
          {'id': 'abc', 'url': '/api/uploads/abc', 'width': 1200, 'height': 900},
        ],
        'quote_of': {
          'id': 3,
          'kind': 'post',
          'identity': 'anonymous',
          'display_name': 'ぽんず',
          'author': null,
          'body': '元',
        },
        'comment_count': 1,
        'created_at': '2026-11-20T01:23:45Z',
        'edited_at': null,
        'can_edit': true,
        'can_delete': true,
      });
      expect(post.isAnnouncement, isTrue);
      expect(post.author?.affiliation, '営業部・主任');
      expect(post.likedByMe, isTrue);
      expect(post.likeCount, 2);
      expect(post.images.single.aspectRatio, closeTo(4 / 3, 0.001));
      expect(post.quoteOf?.shownName, 'ぽんず');
      expect(post.quoteOf?.author, isNull);
      expect(post.copyWith(likedByMe: false, likeCount: 1).likeCount, 1);
      expect(post.withCommentCount(2).commentCount, 2);
      expect(post.withCommentCount(-1).commentCount, 0);
    });

    test('ログイン結果（パスワード再設定が必要）', () {
      final r = AuthResult.fromJson({
        'status': 'password_change_required',
        'token': 't',
        'user': {'id': 1, 'display_name': '管理 太郎', 'must_change_password': true},
        'company': {'id': 1, 'code': 'DEMO', 'name': 'デモ株式会社', 'guidelines_version': 1},
      });
      expect(r.needsPasswordChange, isTrue);
      expect(r.user.mustChangePassword, isTrue);
      expect(r.company.guidelinesVersion, 1);
    });
  });

  test('API エラーの分類', () {
    expect(const ApiException(401, 'session_expired', '').isSessionError, isTrue);
    expect(const ApiException(401, 'invalid_credentials', '').isSessionError, isFalse);
    expect(const ApiException(401, 'invalid_current_password', '').isSessionError, isFalse);
    expect(const ApiException(403, 'password_change_required', '').isPasswordChangeRequired, isTrue);
    expect(
      const ApiException(400, 'password_policy', '', {
        'details': ['8文字以上にしてください'],
      }).details,
      ['8文字以上にしてください'],
    );
  });

  test('接続先 URL の正規化', () {
    expect(AppConfig.normalizeServerUrl(' sns.example.co.jp/ '), 'https://sns.example.co.jp');
    expect(AppConfig.normalizeServerUrl('http://localhost:8790//'), 'http://localhost:8790');
  });
}
