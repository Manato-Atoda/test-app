import 'package:flutter_test/flutter_test.dart';
import 'package:vamos_prototype/data/models.dart';

void main() {
  test('吹き出しブロックを読み込める', () {
    final block = ContentBlock.fromJson({
      'type': 'speech',
      'role': 'a',
      'avatar': 'assets/vamos/images/avatar/a.webp',
      'paragraphs': ['こんにちは', 'よろしくお願いします'],
    });

    expect(block, isA<SpeechBlock>());
    final speech = block as SpeechBlock;
    expect(speech.isAnswer, isTrue);
    expect(speech.paragraphs, hasLength(2));
  });

  test('知らない種類のブロックは区切り線として扱う', () {
    expect(ContentBlock.fromJson({'type': 'unknown'}), isA<DividerBlock>());
  });

  test('トピックのカテゴリーを読み込める', () {
    expect(TopicCategory.fromKey('career'), TopicCategory.career);
    expect(TopicCategory.fromKey('other'), isNull);
  });
}
