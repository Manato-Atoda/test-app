// API のレスポンスを表すモデル（docs/API.md の「共通オブジェクト」）。

typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

bool _bool(Object? v) => v == true;

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

List<Json> _list(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

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
    this.email = '',
    this.bio = '',
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
    email: _str(j['email']),
    bio: _str(j['bio']),
  );

  final int id;
  final String displayName;
  final String employeeCode;
  final String department;
  final String title;
  final int avatarColor;
  final String role;
  final String status;
  final String email;
  final String bio;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';

  /// 「営業部・主任」のような所属表示。
  String get affiliation =>
      [department, title].where((s) => s.isNotEmpty).join('・');
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
    super.email,
    super.bio,
    required this.mustChangePassword,
    required this.passkeyCount,
    required this.lastLoginAt,
    required this.guidelinesAcceptedVersion,
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
      email: base.email,
      bio: base.bio,
      mustChangePassword: _bool(j['must_change_password']),
      passkeyCount: _int(j['passkey_count']),
      lastLoginAt: _date(j['last_login_at']),
      guidelinesAcceptedVersion: _int(j['guidelines_accepted_version']),
    );
  }

  final bool mustChangePassword;
  final int passkeyCount;
  final DateTime? lastLoginAt;
  final int guidelinesAcceptedVersion;
}

class Company {
  const Company({
    required this.id,
    required this.code,
    required this.name,
    required this.guidelines,
    required this.guidelinesVersion,
  });

  factory Company.fromJson(Json j) => Company(
    id: _int(j['id']),
    code: _str(j['code']),
    name: _str(j['name']),
    guidelines: _str(j['guidelines']),
    guidelinesVersion: _int(j['guidelines_version']),
  );

  final int id;
  final String code;
  final String name;
  final String guidelines;
  final int guidelinesVersion;
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
  const AuthResult({
    required this.status,
    required this.token,
    required this.user,
    required this.company,
  });

  factory AuthResult.fromJson(Json j) => AuthResult(
    status: _str(j['status']),
    token: _str(j['token']),
    user: Me.fromJson((j['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
    company: Company.fromJson(
      (j['company'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );

  final String status;
  final String token;
  final Me user;
  final Company company;

  bool get needsPasswordChange => status == 'password_change_required';
}

class ChannelRef {
  const ChannelRef({required this.id, required this.name});

  factory ChannelRef.fromJson(Json j) =>
      ChannelRef(id: _int(j['id']), name: _str(j['name']));

  final int id;
  final String name;
}

class Reaction {
  const Reaction({
    required this.key,
    required this.count,
    required this.reactedByMe,
  });

  factory Reaction.fromJson(Json j) => Reaction(
    key: _str(j['key']),
    count: _int(j['count']),
    reactedByMe: _bool(j['reacted_by_me']),
  );

  final String key;
  final int count;
  final bool reactedByMe;

  /// API の key と表示する絵文字の対応（順番も表示順）。
  static const emojis = <String, String>{
    'like': '👍',
    'thanks': '🙏',
    'clap': '👏',
    'celebrate': '🎉',
    'idea': '💡',
    'eyes': '👀',
  };

  static const labels = <String, String>{
    'like': 'いいね',
    'thanks': 'ありがとう',
    'clap': '拍手',
    'celebrate': 'おめでとう',
    'idea': 'なるほど',
    'eyes': '見ました',
  };

  String get emoji => emojis[key] ?? '❓';
}

class Post {
  const Post({
    required this.id,
    required this.channel,
    required this.author,
    required this.body,
    required this.kind,
    required this.requireAck,
    required this.ackedByMe,
    required this.ackCount,
    required this.reactions,
    required this.commentCount,
    required this.createdAt,
    required this.editedAt,
    required this.canEdit,
    required this.canDelete,
  });

  factory Post.fromJson(Json j) => Post(
    id: _int(j['id']),
    channel: ChannelRef.fromJson(
      (j['channel'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    author: UserSummary.fromJson(
      (j['author'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    body: _str(j['body']),
    kind: _str(j['kind'], 'post'),
    requireAck: _bool(j['require_ack']),
    ackedByMe: _bool(j['acked_by_me']),
    ackCount: _int(j['ack_count']),
    reactions: _list(j['reactions']).map(Reaction.fromJson).toList(),
    commentCount: _int(j['comment_count']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    editedAt: _date(j['edited_at']),
    canEdit: _bool(j['can_edit']),
    canDelete: _bool(j['can_delete']),
  );

  final int id;
  final ChannelRef channel;
  final UserSummary author;
  final String body;
  final String kind;
  final bool requireAck;
  final bool ackedByMe;
  final int ackCount;
  final List<Reaction> reactions;
  final int commentCount;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool canEdit;
  final bool canDelete;

  bool get isAnnouncement => kind == 'announcement';

  Post withCommentCount(int count) => Post(
    id: id,
    channel: channel,
    author: author,
    body: body,
    kind: kind,
    requireAck: requireAck,
    ackedByMe: ackedByMe,
    ackCount: ackCount,
    reactions: reactions,
    commentCount: count < 0 ? 0 : count,
    createdAt: createdAt,
    editedAt: editedAt,
    canEdit: canEdit,
    canDelete: canDelete,
  );

  Reaction? reaction(String key) {
    for (final r in reactions) {
      if (r.key == key) return r;
    }
    return null;
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.author,
    required this.body,
    required this.createdAt,
    required this.hidden,
    required this.canDelete,
  });

  factory Comment.fromJson(Json j) => Comment(
    id: _int(j['id']),
    postId: _int(j['post_id']),
    author: UserSummary.fromJson(
      (j['author'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    body: _str(j['body']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    hidden: _bool(j['hidden']),
    canDelete: _bool(j['can_delete']),
  );

  final int id;
  final int postId;
  final UserSummary author;
  final String body;
  final DateTime createdAt;
  final bool hidden;
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

  bool get isPrivate => visibility == 'private';
  bool get adminsOnly => postPolicy == 'admins';
}

class FeedPage {
  const FeedPage({required this.posts, required this.nextBefore});

  factory FeedPage.fromJson(Json j) => FeedPage(
    posts: _list(j['posts']).map(Post.fromJson).toList(),
    nextBefore: j['next_before'] == null ? null : _int(j['next_before']),
  );

  final List<Post> posts;
  final int? nextBefore;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actor,
    required this.postId,
    required this.excerpt,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromJson(Json j) => AppNotification(
    id: _int(j['id']),
    type: _str(j['type']),
    actor: j['actor'] is Map
        ? UserSummary.fromJson((j['actor'] as Map).cast<String, dynamic>())
        : null,
    postId: j['post_id'] == null ? null : _int(j['post_id']),
    excerpt: _str(j['excerpt']),
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    read: _bool(j['read']),
  );

  final int id;
  final String type;
  final UserSummary? actor;
  final int? postId;
  final String excerpt;
  final DateTime createdAt;
  final bool read;

  AppNotification markRead() => AppNotification(
    id: id,
    type: type,
    actor: actor,
    postId: postId,
    excerpt: excerpt,
    createdAt: createdAt,
    read: true,
  );

  String get description {
    final name = actor?.displayName ?? '誰か';
    switch (type) {
      case 'comment':
        return '$name さんがあなたの投稿にコメントしました';
      case 'mention':
        return '$name さんがあなたをメンションしました';
      case 'announcement':
        return '$name さんがお知らせを投稿しました';
      default:
        return '$name さんからの通知';
    }
  }
}

class NotificationPage {
  const NotificationPage({
    required this.notifications,
    required this.unreadCount,
    required this.nextBefore,
  });

  factory NotificationPage.fromJson(Json j) => NotificationPage(
    notifications: _list(
      j['notifications'],
    ).map(AppNotification.fromJson).toList(),
    unreadCount: _int(j['unread_count']),
    nextBefore: j['next_before'] == null ? null : _int(j['next_before']),
  );

  final List<AppNotification> notifications;
  final int unreadCount;
  final int? nextBefore;
}

class Passkey {
  const Passkey({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
  });

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

  factory PasskeyTicket.fromJson(Json j) => PasskeyTicket(
    ticket: _str(j['ticket']),
    registerUrl: _str(j['register_url']),
  );

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
  const UserProfile({required this.user, required this.posts});

  factory UserProfile.fromJson(Json j) => UserProfile(
    user: UserSummary.fromJson(
      (j['user'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    posts: _list(j['posts']).map(Post.fromJson).toList(),
  );

  final UserSummary user;
  final List<Post> posts;
}

class PostDetail {
  const PostDetail({required this.post, required this.comments});

  factory PostDetail.fromJson(Json j) => PostDetail(
    post: Post.fromJson((j['post'] as Map?)?.cast<String, dynamic>() ?? const {}),
    comments: _list(j['comments']).map(Comment.fromJson).toList(),
  );

  final Post post;
  final List<Comment> comments;
}
