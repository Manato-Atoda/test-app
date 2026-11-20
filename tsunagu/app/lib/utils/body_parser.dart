/// 投稿本文を「ふつうの文字・URL・メンション」に分ける（表示用）。
enum BodySegmentType { text, url, mention }

class BodySegment {
  const BodySegment(this.type, this.text);

  final BodySegmentType type;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is BodySegment && other.type == type && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);

  @override
  String toString() => '${type.name}:$text';
}

final _pattern = RegExp(
  r'(https?://[^\s<>"（）「」、。]+)|((?<![A-Za-z0-9_.-])@[A-Za-z0-9_.-]{1,32})',
);

List<BodySegment> parseBody(String body) {
  final out = <BodySegment>[];
  var index = 0;
  for (final m in _pattern.allMatches(body)) {
    if (m.start > index) {
      out.add(BodySegment(BodySegmentType.text, body.substring(index, m.start)));
    }
    var matched = m.group(0)!;
    var end = m.end;
    if (m.group(1) != null) {
      // 文末の句読点や閉じ括弧は URL に含めない。
      final trimmed = matched.replaceFirst(RegExp(r'[.,!?:;)\]]+$'), '');
      end = m.start + trimmed.length;
      matched = trimmed;
      out.add(BodySegment(BodySegmentType.url, matched));
    } else {
      out.add(BodySegment(BodySegmentType.mention, matched));
    }
    index = end;
  }
  if (index < body.length) {
    out.add(BodySegment(BodySegmentType.text, body.substring(index)));
  }
  return out;
}
