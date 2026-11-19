/// 記事本文を構成する部品（RE_VAMOS の本文 HTML から変換したもの）。
sealed class ContentBlock {
  const ContentBlock();

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'paragraph' => ParagraphBlock(json['text'] as String),
      'heading' => HeadingBlock(json['text'] as String, level: (json['level'] as num?)?.toInt() ?? 2),
      'image' => ImageBlock(json['src'] as String, caption: (json['caption'] as String?) ?? ''),
      'speech' => SpeechBlock(
          isAnswer: json['role'] == 'a',
          avatar: json['avatar'] as String?,
          paragraphs: (json['paragraphs'] as List).cast<String>(),
        ),
      'list' => ListBlock((json['items'] as List).cast<String>()),
      'quote' => QuoteBlock(json['text'] as String),
      'link' => LinkBlock(
          title: (json['title'] as String?) ?? '',
          description: (json['description'] as String?) ?? '',
          source: (json['source'] as String?) ?? '',
          url: (json['url'] as String?) ?? '',
        ),
      _ => const DividerBlock(),
    };
  }
}

final class ParagraphBlock extends ContentBlock {
  const ParagraphBlock(this.text);
  final String text;
}

final class HeadingBlock extends ContentBlock {
  const HeadingBlock(this.text, {this.level = 2});
  final String text;
  final int level;
}

final class ImageBlock extends ContentBlock {
  const ImageBlock(this.src, {this.caption = ''});
  final String src;
  final String caption;
}

/// インタビューの吹き出し。isAnswer が true なら取材相手、false なら聞き手（学生リポーター）。
final class SpeechBlock extends ContentBlock {
  const SpeechBlock({required this.isAnswer, required this.paragraphs, this.avatar});
  final bool isAnswer;
  final String? avatar;
  final List<String> paragraphs;
}

final class ListBlock extends ContentBlock {
  const ListBlock(this.items);
  final List<String> items;
}

final class QuoteBlock extends ContentBlock {
  const QuoteBlock(this.text);
  final String text;
}

final class LinkBlock extends ContentBlock {
  const LinkBlock({required this.title, required this.description, required this.source, required this.url});
  final String title;
  final String description;
  final String source;
  final String url;
}

final class DividerBlock extends ContentBlock {
  const DividerBlock();
}

List<ContentBlock> _blocks(Object? json) =>
    ((json as List?) ?? const []).map((b) => ContentBlock.fromJson(b as Map<String, dynamic>)).toList();

/// 企業インタビュー
class Interview {
  const Interview({
    required this.slug,
    required this.title,
    required this.date,
    required this.readMinutes,
    required this.thumbnail,
    required this.excerpt,
    required this.author,
    required this.company,
    required this.blocks,
  });

  factory Interview.fromJson(Map<String, dynamic> json) => Interview(
        slug: json['slug'] as String,
        title: json['title'] as String,
        date: json['date'] as String,
        readMinutes: (json['readMinutes'] as num?)?.toInt() ?? 0,
        thumbnail: json['thumbnail'] as String?,
        excerpt: (json['excerpt'] as String?) ?? '',
        author: (json['author'] as String?) ?? 'Vamos編集部',
        company: (json['company'] as String?) ?? '',
        blocks: _blocks(json['blocks']),
      );

  final String slug;
  final String title;
  final String date;
  final int readMinutes;
  final String? thumbnail;
  final String excerpt;
  final String author;
  final String company;

  /// 本文。API の一覧では空（詳細を取得したときに入る）
  final List<ContentBlock> blocks;

  bool get hasBody => blocks.isNotEmpty;
}

/// トピックのカテゴリー（RE_VAMOS の VAMOS_TOPIC_CAT）
enum TopicCategory {
  shukatsu('就活'),
  career('転職'),
  news('ニュース');

  const TopicCategory(this.label);
  final String label;

  static TopicCategory? fromKey(String key) =>
      TopicCategory.values.where((c) => c.name == key).firstOrNull;
}

/// 就活・転職のお役立ちトピック
class Topic {
  const Topic({
    required this.id,
    required this.slug,
    required this.category,
    required this.title,
    required this.date,
    required this.author,
    required this.lead,
    required this.excerpt,
    required this.blocks,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
        id: (json['id'] as num).toInt(),
        slug: json['slug'] as String,
        category: TopicCategory.fromKey(json['category'] as String? ?? ''),
        title: json['title'] as String,
        date: (json['date'] as String?) ?? '',
        author: (json['author'] as String?) ?? 'Vamos編集部',
        lead: (json['lead'] as String?) ?? '',
        excerpt: (json['excerpt'] as String?) ?? '',
        blocks: _blocks(json['blocks']),
      );

  final int id;
  final String slug;
  final TopicCategory? category;
  final String title;
  final String date;
  final String author;
  final String lead;
  final String excerpt;
  final List<ContentBlock> blocks;
}

/// 会員情報（RE_VAMOS の members に相当する項目の一部）
class UserAccount {
  const UserAccount({
    required this.email,
    required this.displayName,
    required this.statuses,
    required this.interests,
    required this.areas,
    required this.profileCompleted,
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        email: json['email'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        statuses: ((json['statuses'] as List?) ?? const []).cast<String>(),
        interests: ((json['interests'] as List?) ?? const []).cast<String>(),
        areas: ((json['areas'] as List?) ?? const []).cast<String>(),
        profileCompleted: json['profileCompleted'] == true,
      );

  final String email;
  final String displayName;
  final List<String> statuses;
  final List<String> interests;
  final List<String> areas;
  final bool profileCompleted;

  Map<String, Object?> toJson() => {
        'email': email,
        'displayName': displayName,
        'statuses': statuses,
        'interests': interests,
        'areas': areas,
        'profileCompleted': profileCompleted,
      };
}

/// ログイン状態（トークンと会員情報）
class Session {
  const Session({required this.token, required this.user});

  final String token;
  final UserAccount user;

  Session copyWith({UserAccount? user}) => Session(token: token, user: user ?? this.user);
}
