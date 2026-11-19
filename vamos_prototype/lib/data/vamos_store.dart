import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// アプリ内に同梱したサンプルデータ（試作のため通信はしない）。
class VamosContent {
  const VamosContent({required this.interviews, required this.topics});

  final List<Interview> interviews;
  final List<Topic> topics;

  static Future<VamosContent> load() async {
    final interviews = await rootBundle.loadString('assets/vamos/data/interviews.json');
    final topics = await rootBundle.loadString('assets/vamos/data/topics.json');
    return VamosContent(
      interviews: (jsonDecode(interviews) as List)
          .map((j) => Interview.fromJson(j as Map<String, dynamic>))
          .toList(),
      topics: (jsonDecode(topics) as List).map((j) => Topic.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }
}

/// 保存したインタビュー（試作のため、アプリを閉じると消える）。
final ValueNotifier<Set<String>> savedInterviews = ValueNotifier<Set<String>>(<String>{});

void toggleSaved(String slug) {
  final next = Set<String>.of(savedInterviews.value);
  if (!next.remove(slug)) {
    next.add(slug);
  }
  savedInterviews.value = next;
}
