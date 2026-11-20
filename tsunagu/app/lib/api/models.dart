// API のレスポンスを表すモデル（docs/API.md と docs/API-v2.md の「共通オブジェクト」）。

typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _intOrNull(Object? v) => v == null ? null : _int(v);

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

bool _bool(Object? v) => v == true;

DateTime? _date(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<Json> _list(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

class UserSummary {
  const UserSummary({
    required this.id,
    required this.displayName,
    required this.employeeCode,
    required this.department,
    required this.title,
    required this.avatarColor,
    required this.role,
    required this.status,
    this.avatarUrl,
    this.email = '',
    this.bio = '',
    this.coverUrl,
  });

  factory UserSummary.fromJson(Json j) => UserSummary(
    id: _int(j['id']),
    displayName: _str(j['display_name'], '（不明）'),
    employeeCode: _str(j['employee_code']),
    department: _str(j['department']),
    title: _str(j['title']),
    avatarColor: _int(j['avatar_color']),
    role: _str(j['role'], 'member'),
    status: _str(j['status'], 'active'),
    avatarUrl: _strOrNull(j['avatar_url']),
    email: _str(j['email']),
    bio: _str(j['bio']),
    coverUrl: _strOrNull(j['cover_url']),
  );

  final int id;
  final String displayName;
  final String employeeCode;
  final String department;
  final String title;
  final int avatarColor;
  final String role;
  final String status;
  final String? avatarUrl;
  final String email;
  final String bio;
  final String? coverUrl;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';

  /// 「営業部・主任」のような所属表示。
  String get affiliation => [department, title].where((s) => s.isNotEmpty).join('・');
}

class Me extends UserSummary {
  const Me({
    required super.id,
    required super.displayName,
    required super.employeeCode,
    required super.department,
    required super.title,
    required super.avatarColor,
    required super.role,
    required super.status,
    super.avatarUrl,
    super.email,
    super.bio,
    super.coverUrl,
    required this.mustChangePassword,
    required this.passkeyCount,
    required this.lastLoginAt,
    required this.guidelinesAcceptedVersion,
    this.nickname,
  });

  factory Me.fromJson(Json j) {
    final base = UserSummary.fromJson(j);
    return Me(
      id: base.id,
      displayName: base.displayName,
      employeeCode: base.employeeCode,
      department: base.department,
      title: base.title,
      avatarColor: base.avatarColor,
      role: base.role,
      status: base.status,
      avatarUrl: base.avatarUrl,
      email: base.email,
      bio: base.bio,
      coverUrl: base.coverUrl,
      mustChangePassword: _bool(j['must_change_password']),
      passkeyCount: _int(j['passkey_count']),
      lastLoginAt: _date(j['last_login_at']),
      guidelinesAcceptedVersion: _int(j['guidelines_accepted_version']),
      nickname: _strOrNull(j['nickname']),
    );
  }

  final bool mustChangePassword;
  final int passkeyCount;
  final DateTime? lastLoginAt;
  final int guidelinesAcceptedVersion;

  /// 匿名で投稿するときの表示名（あだ名）。
  final String? nickname;
}

class QuickComment {
  const QuickComment({required this.emoji, required this.text});

  factory QuickComment.fromJson(Json j) => QuickComment(emoji: _str(j['emoji']), text: _str(j['text']));

  final String emoji;
  final String text;

  /// サーバーが返さないときの既定（Galaxia と同じ）。
  static const defaults = <QuickComment>[
    QuickComment(emoji: '👏', text: 'ナイス！'),
    QuickComment(emoji: '🙌', text: 'お疲れさまです'),
    QuickComment(emoji: '🔥', text: '最高！'),
    QuickComment(emoji: '💡', text: '参考になります'),
    QuickComment(emoji: '✨', text: 'いいですね'),
    QuickComment(emoji: '💪', text: 'がんばってください'),
    QuickComment(emoji: '🎉', text: 'おめでとうございます'),
    QuickComment(emoji: '🤝', text: 'ありがとうございます'),
    QuickComment(emoji: '👀', text: '気になる'),
    QuickComment(emoji: '🍵', text: 'お疲れさま'),
  ];
}

class CompanyFeatures {
  const CompanyFeatures({this.identityDepartment = false, this.identityAnonymous = false, this.watermark = false});

  factory CompanyFeatures.fromJson(Json? j) => j == null
      ? const CompanyFeatures()
      : CompanyFeatures(
          identityDepartment: _bool(j['identity_department']),
          identityAnonymous: _bool(j['identity_anonymous']),
          watermark: _bool(j['watermark']),
        );

  final bool identityDepartment;
  final bool identityAnonymous;
  final bool watermark;
}

class Company {
  const Company({
    required this.id,
    required this.code,
    required this.name,
    required this.guidelines,
    required this.guidelinesVersion,
    this.features = const CompanyFeatures(),
    this.quickComments = QuickComment.defaults,
  });

  factory Company.fromJson(Json j) {
    final quick = _list(j['quick_comments']).map(QuickComment.fromJson).toList();
    return Company(
      id: _int(j['id']),
      code: _str(j['code']),
      name: _str(j['name']),
      guidelines: _str(j['guidelines']),
      guidelinesVersion: _int(j['guidelines_version']),
      features: CompanyFeatures.fromJson(_map(j['features'])),
      quickComments: quick.isEmpty ? QuickComment.defaults : quick,
    );
  }

  final int id;
  final String code;
  final String name;
  final String guidelines;
  final int guidelinesVersion;
  final CompanyFeatures features;
  final List<QuickComment> quickComments;
}

class PasswordPolicy {
  const PasswordPolicy({
    this.minLength = 8,
    this.maxLength = 128,
    this.requireLetter = true,
    this.requireDigit = true,
    this.requireSymbol = false,
    this.allowedSymbols = defaultSymbols,
  });

  static const defaultSymbols = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';

  factory PasswordPolicy.fromJson(Json j) => PasswordPolicy(
    minLength: _int(j['min_length'], 8),
    maxLength: _int(j['max_length'], 128),
    requireLetter: j['require_letter'] != false,
    requireDigit: j['require_digit'] != false,
    requireSymbol: _bool(j['require_symbol']),
    allowedSymbols: _str(j['allowed_symbols'], defaultSymbols),
  );

  final int minLength;
  final int maxLength;
  final bool requireLetter;
  final bool requireDigit;
  final bool requireSymbol;
  final String allowedSymbols;
}

/// ログイン・パスワード変更・パスキー交換の結果。
class AuthResult {
  const AuthResult({required this.status, required this.token, required this.user, required this.company});

  factory AuthResult.fromJson(Json j) => AuthResult(
    status: _str(j['status']),
    token: _str(j['token']),
    user: Me.fromJson(_map(j['user']) ?? const {}),
    company: Company.fromJson(_map(j['company']) ?? const {}),
  );

  final String status;
  final String token;
  final Me user;
  final Company company;

  bool get needsPasswordChange => status == 'password_change_required';
}

/// 発信者（実名・部署・匿名）。
enum Identity {
  real('real', '実名'),
  department('department', '部署'),
  anonymous('anonymous', '匿名');

  const Identity(this.value, this.label);

  final String value;
  final String label;

  static Identity parse(Object? v) => Identity.values.firstWhere((e) => e.value == v, orElse: () => Identity.real);
}

class ChannelRef {
  const ChannelRef({required this.id, required this.name, this.emoji});

  factory ChannelRef.fromJson(Json j) =>
      ChannelRef(id: _int(j['id']), name: _str(j['name']), emoji: _strOrNull(j['emoji']));

  final int id;
  final String name;
  final String? emoji;

  String get label => emoji == null ? '#$name' : '$emoji $name';
}

class ImageRef {
  const ImageRef({required this.id, required this.url, required this.width, required this.height});

  factory ImageRef.fromJson(Json j) =>
      ImageRef(id: _str(j['id']), url: _str(j['url']), width: _int(j['width']), height: _int(j['height']));

  final String id;
  final String url;
  final int width;
  final int height;

  double get aspectRatio => width > 0 && height > 0 ? width / height : 4 / 3;
}

/// 投稿・コメント・森の書き込みに共通する「誰が書いたか」。
mixin Authored {
  UserSummary? get author;
  Identity get identity;
  String? get displayNameRaw;
  bool get isMine;

  /// 画面に出す名前。実名なら氏名、部署・匿名なら表示名。
  String get shownName {
    final a = author;
    if (identity == Identity.real && a != null) return a.displayName;
    return displayNameRaw ?? (identity == Identity.department ? '部署' : '匿名');
  }
}

class Post with Authored {
  const Post({
    required this.id,
    required this.kind,
    required this.channel,
    required this.author,
    required this.identity,
    required this.displayNameRaw,
    required this.isMine,
    required this.body,
    required this.images,
    required this.quoteOf,
    required this.requireAck,
    required this.ackedByMe,
    required this.ackCount,
    required this.likeCount,
    required this.likedByMe,
    required this.commentCount,
    required this.shareCount,
    required this.sharedByMe,
    required this.bookmarkedByMe,
    required this.viewCount,
    required this.createdAt,
    required this.editedAt,
    required this.canEdit,
    required this.canDelete,
  });

  factory Post.fromJson(Json j) {
    final channel = _map(j['channel']);
    final author = _map(j['author']);
    final quote = _map(j['quote_of']);
    return Post(
      id: _int(j['id']),
      kind: _str(j['kind'], 'post'),
      channel: channel == null ? null : ChannelRef.fromJson(channel),
      author: author == null ? null : UserSummary.fromJson(author),
      identity: Identity.parse(j['identity']),
      displayNameRaw: _strOrNull(j['display_name']),
      isMine: _bool(j['is_mine']),
      body: _str(j['body']),
      images: _list(j['images']).map(ImageRef.fromJson).toList(),
      quoteOf: quote == null ? null : Post.fromJson(quote),
      requireAck: _bool(j['require_ack']),
      ackedByMe: _bool(j['acked_by_me']),
      ackCount: _int(j['ack_count']),
      likeCount: _int(j['like_count']),
      likedByMe: _bool(j['liked_by_me']),
      commentCount: _int(j['comment_count']),
      shareCount: _int(j['share_count']),
      sharedByMe: _bool(j['shared_by_me']),
      bookmarkedByMe: _bool(j['bookmarked_by_me']),
      viewCount: _int(j['view_count']),
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      editedAt: _date(j['edited_at']),
      canEdit: _bool(j['can_edit']),
      canDelete: _bool(j['can_delete']),
    );
  }

  final int id;
  final String kind;
  final ChannelRef? channel;
  @override
  final UserSummary? author;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  final bool isMine;
  final String body;
  final List<ImageRef> images;
  final Post? quoteOf;
  final bool requireAck;
  final bool ackedByMe;
  final int ackCount;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final int shareCount;
  final bool sharedByMe;
  final bool bookmarkedByMe;
  final int viewCount;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool canEdit;
  final bool canDelete;

  bool get isAnnouncement => kind == 'announcement';
  bool get isCommit => kind == 'commit';

  /// 「そのままシェア」した投稿（本文なし・quote_of を表示）。
  bool get isShare => kind == 'share';

  Post copyWith({
    int? likeCount,
    bool? likedByMe,
    int? commentCount,
    bool? bookmarkedByMe,
    bool? sharedByMe,
    int? shareCount,
    Post? quoteOf,
  }) => Post(
    id: id,
    kind: kind,
    channel: channel,
    author: author,
    identity: identity,
    displayNameRaw: displayNameRaw,
    isMine: isMine,
    body: body,
    images: images,
    quoteOf: quoteOf ?? this.quoteOf,
    requireAck: requireAck,
    ackedByMe: ackedByMe,
    ackCount: ackCount,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    commentCount: (commentCount ?? this.commentCount) < 0 ? 0 : (commentCount ?? this.commentCount),
    shareCount: shareCount ?? this.shareCount,
    sharedByMe: sharedByMe ?? this.sharedByMe,
    bookmarkedByMe: bookmarkedByMe ?? this.bookmarkedByMe,
    viewCount: viewCount,
    createdAt: createdAt,
    editedAt: editedAt,
    canEdit: canEdit,
    canDelete: canDelete,
  );

  Post withCommentCount(int count) => copyWith(commentCount: count);
}

class Comment with Authored {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.identity,
    required this.displayNameRaw,
    required this.isMine,
    required this.body,
    required this.isQuick,
    required this.likeCount,
    required this.likedByMe,
    required this.createdAt,
    required this.editedAt,
    required this.hidden,
    required this.canEdit,
    required this.canDelete,
  });

  factory Comment.fromJson(Json j) {
    final author = _map(j['author']);
    return Comment(
      id: _int(j['id']),
      postId: _int(j['post_id']),
      author: author == null ? null : UserSummary.fromJson(author),
      identity: Identity.parse(j['identity']),
      displayNameRaw: _strOrNull(j['display_name']),
      isMine: _bool(j['is_mine']),
      body: _str(j['body']),
      isQuick: _bool(j['is_quick']),
      likeCount: _int(j['like_count']),
      likedByMe: _bool(j['liked_by_me']),
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      editedAt: _date(j['edited_at']),
      hidden: _bool(j['hidden']),
      canEdit: _bool(j['can_edit']),
      canDelete: _bool(j['can_delete']),
    );
  }

  final int id;
  final int postId;
  @override
  final UserSummary? author;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  final bool isMine;
  final String body;
  final bool isQuick;
  final int likeCount;
  final bool likedByMe;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool hidden;
  final bool canEdit;
  final bool canDelete;
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.companyWide,
    required this.postPolicy,
    required this.isMember,
    required this.canPost,
    required this.memberCount,
    required this.archived,
    this.emoji,
    this.unreadCount = 0,
  });

  factory Channel.fromJson(Json j) => Channel(
    id: _int(j['id']),
    name: _str(j['name']),
    description: _str(j['description']),
    visibility: _str(j['visibility'], 'open'),
    companyWide: _bool(j['company_wide']),
    postPolicy: _str(j['post_policy'], 'everyone'),
    isMember: _bool(j['is_member']),
    canPost: _bool(j['can_post']),
    memberCount: _int(j['member_count']),
    archived: _bool(j['archived']),
    emoji: _strOrNull(j['emoji']),
    unreadCount: _int(j['unread_count']),
  );

  final int id;
  final String name;
  final String description;
  final String visibility;
  final bool companyWide;
  final String postPolicy;
  final bool isMember;
  final bool canPost;
  final int memberCount;
  final bool archived;
  final String? emoji;
  final int unreadCount;

  bool get isPrivate => visibility == 'private';
  bool get adminsOnly => postPolicy == 'admins';
  String get label => emoji == null ? '#$name' : '$emoji $name';

  Channel withUnread(int count) => Channel(
    id: id,
    name: name,
    description: description,
    visibility: visibility,
    companyWide: companyWide,
    postPolicy: postPolicy,
    isMember: isMember,
    canPost: canPost,
    memberCount: memberCount,
    archived: archived,
    emoji: emoji,
    unreadCount: count,
  );
}

class FeedPage {
  const FeedPage({required this.posts, required this.nextBefore});

  factory FeedPage.fromJson(Json j) =>
      FeedPage(posts: _list(j['posts']).map(Post.fromJson).toList(), nextBefore: _intOrNull(j['next_before']));

  final List<Post> posts;
  final int? nextBefore;
}

class Draft {
  const Draft({
    required this.id,
    required this.body,
    required this.identity,
    required this.channelId,
    required this.updatedAt,
  });

  factory Draft.fromJson(Json j) => Draft(
    id: _int(j['id']),
    body: _str(j['body']),
    identity: Identity.parse(j['identity']),
    channelId: _intOrNull(j['channel_id']),
    updatedAt: _date(j['updated_at']),
  );

  final int id;
  final String body;
  final Identity identity;
  final int? channelId;
  final DateTime? updatedAt;
}

/// 通知の飛び先。
class NotificationTarget {
  const NotificationTarget({required this.type, required this.id});

  final String type; // post | question
  final int id;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actor,
    required this.actorName,
    required this.postId,
    required this.target,
    required this.excerpt,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Json j) {
    final t = _map(j['target']);
    final postId = _intOrNull(j['post_id']);
    return AppNotification(
      id: _int(j['id']),
      type: _str(j['type']),
      actor: _map(j['actor']) == null ? null : UserSummary.fromJson(_map(j['actor'])!),
      actorName: _strOrNull(j['actor_name']),
      postId: postId,
      target: t != null
          ? NotificationTarget(type: _str(t['type'], 'post'), id: _int(t['id']))
          : (postId != null ? NotificationTarget(type: 'post', id: postId) : null),
      excerpt: _str(j['excerpt']),
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      read: _bool(j['read']),
    );
  }

  final int id;
  final String type;
  final UserSummary? actor;
  final String? actorName;
  final int? postId;
  final NotificationTarget? target;
  final String excerpt;
  final DateTime createdAt;
  final bool read;

  AppNotification markRead() => AppNotification(
    id: id,
    type: type,
    actor: actor,
    actorName: actorName,
    postId: postId,
    target: target,
    excerpt: excerpt,
    createdAt: createdAt,
    read: true,
  );

  String get who => actor?.displayName ?? actorName ?? '誰か';

  String get description {
    final name = who;
    switch (type) {
      case 'comment':
        return '$name さんがあなたの投稿にコメントしました';
      case 'mention':
        return '$name さんがあなたをメンションしました';
      case 'announcement':
        return '$name さんがお知らせを投稿しました';
      case 'answer':
        return '$name さんがあなたの質問に回答しました';
      case 'answer_comment':
        return '$name さんがあなたの回答にコメントしました';
      case 'share':
        return '$name さんがあなたの投稿をシェアしました';
      case 'quote':
        return '$name さんがあなたの投稿を引用しました';
      default:
        return '$name さんからの通知';
    }
  }
}

class NotificationPage {
  const NotificationPage({required this.notifications, required this.unreadCount, required this.nextBefore});

  factory NotificationPage.fromJson(Json j) => NotificationPage(
    notifications: _list(j['notifications']).map(AppNotification.fromJson).toList(),
    unreadCount: _int(j['unread_count']),
    nextBefore: _intOrNull(j['next_before']),
  );

  final List<AppNotification> notifications;
  final int unreadCount;
  final int? nextBefore;
}

/// 森の「答え待ち」の程度。
enum Urgency {
  calm,
  soft,
  warm,
  hot;

  static Urgency parse(Object? v) => Urgency.values.firstWhere((e) => e.name == v, orElse: () => Urgency.calm);

  String? get label => switch (this) {
    Urgency.calm => null,
    Urgency.soft => 'ちょっと聞かれてるかも',
    Urgency.warm => '数日 答え待ちです',
    Urgency.hot => '長く答え待ちです',
  };
}

class Badges {
  const Badges({
    this.notifications = 0,
    this.forestHasNew = false,
    this.forestUrgency = Urgency.calm,
    this.commitHasNew = false,
    this.announcementsUnacked = 0,
    this.channelsUnread = 0,
  });

  factory Badges.fromJson(Json j) => Badges(
    notifications: _int(j['notifications']),
    forestHasNew: _bool(j['forest_has_new']),
    forestUrgency: Urgency.parse(j['forest_urgency']),
    commitHasNew: _bool(j['commit_has_new']),
    announcementsUnacked: _int(j['announcements_unacked']),
    channelsUnread: _int(j['channels_unread']),
  );

  final int notifications;
  final bool forestHasNew;
  final Urgency forestUrgency;
  final bool commitHasNew;
  final int announcementsUnacked;
  final int channelsUnread;

  Badges copyWith({int? notifications, bool? forestHasNew, bool? commitHasNew}) => Badges(
    notifications: notifications ?? this.notifications,
    forestHasNew: forestHasNew ?? this.forestHasNew,
    forestUrgency: forestUrgency,
    commitHasNew: commitHasNew ?? this.commitHasNew,
    announcementsUnacked: announcementsUnacked,
    channelsUnread: channelsUnread,
  );
}

class TrendingPost {
  const TrendingPost({
    required this.id,
    required this.excerpt,
    required this.displayName,
    required this.likeCount,
    required this.commentCount,
  });

  factory TrendingPost.fromJson(Json j) => TrendingPost(
    id: _int(j['id']),
    excerpt: _str(j['excerpt']),
    displayName: _str(j['display_name']),
    likeCount: _int(j['like_count']),
    commentCount: _int(j['comment_count']),
  );

  final int id;
  final String excerpt;
  final String displayName;
  final int likeCount;
  final int commentCount;
}

class RecentReaction {
  const RecentReaction({
    required this.type,
    required this.actor,
    required this.displayName,
    required this.postId,
    required this.excerpt,
    required this.createdAt,
  });

  factory RecentReaction.fromJson(Json j) => RecentReaction(
    type: _str(j['type']),
    actor: _map(j['actor']) == null ? null : UserSummary.fromJson(_map(j['actor'])!),
    displayName: _strOrNull(j['display_name']),
    postId: _int(j['post_id']),
    excerpt: _str(j['excerpt']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
  );

  final String type; // like | comment
  final UserSummary? actor;
  final String? displayName;
  final int postId;
  final String excerpt;
  final DateTime createdAt;
}

class Highlights {
  const Highlights({
    required this.membersToday,
    required this.active7d,
    required this.trending,
    required this.recentReactions,
  });

  factory Highlights.fromJson(Json j) => Highlights(
    membersToday: _list(j['members_today']).map(UserSummary.fromJson).toList(),
    active7d: _int(j['active_7d']),
    trending: _list(j['trending']).map(TrendingPost.fromJson).toList(),
    recentReactions: _list(j['recent_reactions']).map(RecentReaction.fromJson).toList(),
  );

  final List<UserSummary> membersToday;
  final int active7d;
  final List<TrendingPost> trending;
  final List<RecentReaction> recentReactions;
}

// ---------------------------------------------------------------- わからんの森

class CategoryRef {
  const CategoryRef({required this.id, required this.name, this.emoji});

  factory CategoryRef.fromJson(Json j) =>
      CategoryRef(id: _int(j['id']), name: _str(j['name']), emoji: _strOrNull(j['emoji']));

  final int id;
  final String name;
  final String? emoji;

  String get label => emoji == null ? name : '$emoji $name';
}

class ForestCategory {
  const ForestCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.questionCount,
    required this.unansweredCount,
  });

  factory ForestCategory.fromJson(Json j) => ForestCategory(
    id: _int(j['id']),
    name: _str(j['name']),
    emoji: _strOrNull(j['emoji']),
    description: _str(j['description']),
    questionCount: _int(j['question_count']),
    unansweredCount: _int(j['unanswered_count']),
  );

  final int id;
  final String name;
  final String? emoji;
  final String description;
  final int questionCount;
  final int unansweredCount;

  CategoryRef get ref => CategoryRef(id: id, name: name, emoji: emoji);
}

class Question with Authored {
  const Question({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.identity,
    required this.displayNameRaw,
    required this.author,
    required this.isMine,
    required this.answerCount,
    required this.viewCount,
    required this.createdAt,
    required this.canDelete,
  });

  factory Question.fromJson(Json j) => Question(
    id: _int(j['id']),
    category: CategoryRef.fromJson(_map(j['category']) ?? const {}),
    title: _str(j['title']),
    body: _str(j['body']),
    identity: Identity.parse(j['identity']),
    displayNameRaw: _strOrNull(j['display_name']),
    author: _map(j['author']) == null ? null : UserSummary.fromJson(_map(j['author'])!),
    isMine: _bool(j['is_mine']),
    answerCount: _int(j['answer_count']),
    viewCount: _int(j['view_count']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    canDelete: _bool(j['can_delete']),
  );

  final int id;
  final CategoryRef category;
  final String title;
  final String body;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  final UserSummary? author;
  @override
  final bool isMine;
  final int answerCount;
  final int viewCount;
  final DateTime createdAt;
  final bool canDelete;

  bool get unanswered => answerCount == 0;
}

class AnswerComment with Authored {
  const AnswerComment({
    required this.id,
    required this.body,
    required this.identity,
    required this.displayNameRaw,
    required this.author,
    required this.isMine,
    required this.createdAt,
    required this.canDelete,
  });

  factory AnswerComment.fromJson(Json j) => AnswerComment(
    id: _int(j['id']),
    body: _str(j['body']),
    identity: Identity.parse(j['identity']),
    displayNameRaw: _strOrNull(j['display_name']),
    author: _map(j['author']) == null ? null : UserSummary.fromJson(_map(j['author'])!),
    isMine: _bool(j['is_mine']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    canDelete: _bool(j['can_delete']),
  );

  final int id;
  final String body;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  final UserSummary? author;
  @override
  final bool isMine;
  final DateTime createdAt;
  final bool canDelete;
}

class Answer with Authored {
  const Answer({
    required this.id,
    required this.questionId,
    required this.body,
    required this.identity,
    required this.displayNameRaw,
    required this.author,
    required this.isMine,
    required this.likeCount,
    required this.likedByMe,
    required this.comments,
    required this.createdAt,
    required this.canDelete,
  });

  factory Answer.fromJson(Json j) => Answer(
    id: _int(j['id']),
    questionId: _int(j['question_id']),
    body: _str(j['body']),
    identity: Identity.parse(j['identity']),
    displayNameRaw: _strOrNull(j['display_name']),
    author: _map(j['author']) == null ? null : UserSummary.fromJson(_map(j['author'])!),
    isMine: _bool(j['is_mine']),
    likeCount: _int(j['like_count']),
    likedByMe: _bool(j['liked_by_me']),
    comments: _list(j['comments']).map(AnswerComment.fromJson).toList(),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    canDelete: _bool(j['can_delete']),
  );

  final int id;
  final int questionId;
  final String body;
  @override
  final Identity identity;
  @override
  final String? displayNameRaw;
  @override
  final UserSummary? author;
  @override
  final bool isMine;
  final int likeCount;
  final bool likedByMe;
  final List<AnswerComment> comments;
  final DateTime createdAt;
  final bool canDelete;

  Answer withComments(List<AnswerComment> list) => Answer(
    id: id,
    questionId: questionId,
    body: body,
    identity: identity,
    displayNameRaw: displayNameRaw,
    author: author,
    isMine: isMine,
    likeCount: likeCount,
    likedByMe: likedByMe,
    comments: list,
    createdAt: createdAt,
    canDelete: canDelete,
  );
}

class ForestHome {
  const ForestHome({required this.categories, required this.unanswered, required this.recent, required this.urgency});

  factory ForestHome.fromJson(Json j) => ForestHome(
    categories: _list(j['categories']).map(ForestCategory.fromJson).toList(),
    unanswered: _list(j['unanswered']).map(Question.fromJson).toList(),
    recent: _list(j['recent']).map(Question.fromJson).toList(),
    urgency: Urgency.parse(j['urgency']),
  );

  final List<ForestCategory> categories;
  final List<Question> unanswered;
  final List<Question> recent;
  final Urgency urgency;
}

class QuestionPage {
  const QuestionPage({required this.questions, required this.nextBefore});

  factory QuestionPage.fromJson(Json j) => QuestionPage(
    questions: _list(j['questions']).map(Question.fromJson).toList(),
    nextBefore: _intOrNull(j['next_before']),
  );

  final List<Question> questions;
  final int? nextBefore;
}

class QuestionDetail {
  const QuestionDetail({required this.question, required this.answers});

  factory QuestionDetail.fromJson(Json j) => QuestionDetail(
    question: Question.fromJson(_map(j['question']) ?? const {}),
    answers: _list(j['answers']).map(Answer.fromJson).toList(),
  );

  final Question question;
  final List<Answer> answers;
}

// ---------------------------------------------------------------- その他

class Passkey {
  const Passkey({required this.id, required this.name, required this.createdAt, required this.lastUsedAt});

  factory Passkey.fromJson(Json j) => Passkey(
    id: _int(j['id']),
    name: _str(j['name'], 'パスキー'),
    createdAt: _date(j['created_at']),
    lastUsedAt: _date(j['last_used_at']),
  );

  final int id;
  final String name;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
}

class PasskeyTicket {
  const PasskeyTicket({required this.ticket, required this.registerUrl});

  factory PasskeyTicket.fromJson(Json j) =>
      PasskeyTicket(ticket: _str(j['ticket']), registerUrl: _str(j['register_url']));

  final String ticket;
  final String registerUrl;
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.client,
    required this.authMethod,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  factory SessionInfo.fromJson(Json j) => SessionInfo(
    id: _int(j['id']),
    client: _str(j['client'], '不明な端末'),
    authMethod: _str(j['auth_method']),
    createdAt: _date(j['created_at']),
    lastSeenAt: _date(j['last_seen_at']),
    current: _bool(j['current']),
  );

  final int id;
  final String client;
  final String authMethod;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final bool current;

  String get authMethodLabel => switch (authMethod) {
    'password' => 'パスワード',
    'passkey' => 'パスキー',
    _ => authMethod,
  };
}

class AckStatus {
  const AckStatus({required this.acked, required this.notAcked});

  factory AckStatus.fromJson(Json j) => AckStatus(
    acked: _list(j['acked']).map(UserSummary.fromJson).toList(),
    notAcked: _list(j['not_acked']).map(UserSummary.fromJson).toList(),
  );

  final List<UserSummary> acked;
  final List<UserSummary> notAcked;
}

class UserProfile {
  const UserProfile({required this.user, required this.posts, required this.commits, required this.questions});

  factory UserProfile.fromJson(Json j) => UserProfile(
    user: UserSummary.fromJson(_map(j['user']) ?? const {}),
    posts: _list(j['posts']).map(Post.fromJson).toList(),
    commits: _list(j['commits']).map(Post.fromJson).toList(),
    questions: _list(j['questions']).map(Question.fromJson).toList(),
  );

  final UserSummary user;
  final List<Post> posts;
  final List<Post> commits;
  final List<Question> questions;

  UserProfile copyWith({List<Post>? posts, List<Post>? commits}) =>
      UserProfile(user: user, posts: posts ?? this.posts, commits: commits ?? this.commits, questions: questions);
}

class PostDetail {
  const PostDetail({required this.post, required this.comments});

  factory PostDetail.fromJson(Json j) => PostDetail(
    post: Post.fromJson(_map(j['post']) ?? const {}),
    comments: _list(j['comments']).map(Comment.fromJson).toList(),
  );

  final Post post;
  final List<Comment> comments;
}
