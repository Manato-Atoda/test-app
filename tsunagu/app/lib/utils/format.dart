/// 日時の表示（端末のローカル時刻）。
String relativeTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inSeconds < 60) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24 && current.day == time.day) return '${diff.inHours}時間前';
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  if (time.year == yesterday.year && time.month == yesterday.month && time.day == yesterday.day) {
    return '昨日 ${_hm(time)}';
  }
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  if (time.year == current.year) return '${time.month}月${time.day}日 ${_hm(time)}';
  return '${time.year}年${time.month}月${time.day}日';
}

String fullDateTime(DateTime? time) {
  if (time == null) return '—';
  return '${time.year}/${_pad2(time.month)}/${_pad2(time.day)} ${_hm(time)}';
}

String _hm(DateTime t) => '${t.hour}:${_pad2(t.minute)}';

String _pad2(int v) => v.toString().padLeft(2, '0');
