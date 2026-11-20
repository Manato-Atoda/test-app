# M（マル） API 追加・変更（v2：Galaxia 寄せ）

[API.md](API.md)（v1）からの差分。ここに書いていない API・項目は v1 のまま。
サービス名は「つなぐ」から「M」（読み方：マル）に変わる（`/api/meta` の `service_name` は `"M"`）。
コード上の識別子（`tsunagu` パッケージ名・URL スキーム `tsunagu://`）は変えない。

## 発信者（identity）

投稿・コメント・森の質問／回答／回答コメントは、発信者を選べる。

| identity | 表示 | 条件 |
| --- | --- | --- |
| `real` | 氏名 | いつでも |
| `department` | 部署名（例「営業部」） | 企業設定で許可・自分の部署が登録済み |
| `anonymous` | 自分のあだ名（ニックネーム） | 企業設定で許可・あだ名を登録済み |

- お知らせ・COMMIT は常に `real`。
- 条件を満たさないと `400 identity_unavailable`（message: 「プロフィールで匿名表示名（あだ名）を設定してください」など）。
- `real` 以外のとき、API は `author: null`、`display_name` に表示名を入れる。自分のものは `is_mine: true`。
  管理者も通常の画面では本人を見られない（通報の対応画面 `/api/admin/reports` だけ本人がわかる）。
- 匿名・部署名の投稿はプロフィールの投稿一覧に出ない。

## 共通オブジェクト（変更）

```jsonc
// UserSummary（追加）
{ ..., "avatar_url": "/api/uploads/abc..." | null }

// Me（追加）
{ ..., "nickname": "ぽんず" | null, "cover_url": "/api/uploads/..." | null }

// Company（追加）
{ ..., "features": {"identity_department": true, "identity_anonymous": true, "watermark": false},
  "quick_comments": [{"emoji": "👏", "text": "ナイス！"}, ...] }

// Image
{"id": "k3J9...", "url": "/api/uploads/k3J9...", "width": 1200, "height": 900}

// Post（全体）
{"id": 10,
 "kind": "post" | "announcement" | "commit" | "share",
 "channel": {"id": 1, "name": "全社", "emoji": "🏢"} | null,   // commit は null
 "author": UserSummary | null,          // identity が real 以外なら null
 "identity": "real" | "department" | "anonymous",
 "display_name": "営業部" | null,        // real 以外のときの表示名
 "is_mine": true,
 "body": "本文（share のときは空）",
 "images": [Image],                     // 最大 4 枚
 "quote_of": Post | null,               // 引用・シェア元（入れ子は 1 段だけ。元が消えたら null）
 "require_ack": false, "acked_by_me": false, "ack_count": 0,
 "like_count": 3, "liked_by_me": true,  // 誰が押したかは返さない
 "comment_count": 2,
 "share_count": 1, "shared_by_me": false,
 "bookmarked_by_me": false,
 "view_count": 12,                      // 見た人数（重複なし）
 "created_at": "...", "edited_at": null,
 "can_edit": true, "can_delete": true}

// Comment（全体）
{"id": 5, "post_id": 10, "author": UserSummary | null, "identity": "real", "display_name": null,
 "is_mine": true, "body": "…", "is_quick": false, "like_count": 1, "liked_by_me": false,
 "hidden": false, "created_at": "...", "edited_at": null, "can_edit": true, "can_delete": true}

// Channel（追加）
{ ..., "emoji": "💬" | null, "unread_count": 3 }
```

v1 の `reactions`（6 種類）は廃止し、ハートの「いいね」1 種類にする（既存データはいいねに移す）。

## 投稿まわり

| API | 内容 |
| --- | --- |
| `POST /api/uploads` | 画像のアップロード。本文は画像そのもの（`Content-Type: image/jpeg` / `image/png` / `image/webp`、8MB まで）。→ `Image` |
| `GET /api/uploads/{id}` | 画像（要ログイン・同じ企業のみ）。アプリは `Authorization` ヘッダー付きで読み込む |
| `GET /api/feed?after={id}` | `after` より新しい投稿（最大 50 件、新しい順）。「新しい投稿があります」の判定用。他の引数は v1 のまま |
| `POST /api/posts` | `{"channel_id", "body", "kind", "require_ack", "identity", "image_ids": [..], "quote_of": 12}`。本文か画像のどちらかは必須。引用は元の投稿と同じチャンネルに入る（`channel_id` は無視） |
| `PATCH /api/posts/{id}` | `{"body"}`（v1 のまま） |
| `PUT /api/posts/{id}/like` / `DELETE` | いいね → `{"post": Post}` |
| `PUT /api/posts/{id}/bookmark` / `DELETE` | 保存 → `{"post": Post}` |
| `POST /api/posts/{id}/share` | そのままシェア → `{"post": Post}`（作られた share。元の投稿と同じチャンネル） |
| `DELETE /api/posts/{id}/share` | 自分のシェアを取り消す → `{"post": Post}`（元の投稿） |
| `POST /api/posts/views` | `{"ids": [10, 11]}` 見た投稿を記録 → `204` |
| `GET /api/bookmarks?kind=post|commit&before=` | 保存した投稿 → `{"posts", "next_before"}`（保存した新しい順） |
| `POST /api/posts/{id}/comments` | `{"body", "identity", "quick_index": 0}`（`quick_index` を送ると定型コメント。`body` は不要） |
| `PATCH /api/comments/{id}` | `{"body"}` → `{"comment"}`（投稿者のみ） |
| `PUT /api/comments/{id}/like` / `DELETE` | → `{"comment": Comment}` |
| `GET /api/drafts` | → `{"drafts": [{"id", "body", "identity", "channel_id", "updated_at"}]}`（最大 20 件） |
| `POST /api/drafts` | `{"body", "identity", "channel_id"}` → `{"draft"}` |
| `DELETE /api/drafts/{id}` | → `204` |

フィードに出る `kind: "share"` は「〇〇さんがシェア」として `quote_of` を表示する。いいね・コメントなどの操作は `quote_of` の投稿に対して行う。
ホームのタイムラインには COMMIT（とそのシェア・引用）は出ない。

## COMMIT（何を、いつまでに、どこまでやるかの宣言）

| API | 内容 |
| --- | --- |
| `GET /api/commits?user_id=&period=today|week|month|all&before=` | → `{"posts": [Post], "next_before"}`（COMMIT とそのシェア・引用） |
| `POST /api/commits` | `{"body", "image_ids"}` → `{"post"}`（常に実名） |

いいね・コメント・保存・シェア・削除などは通常の投稿 API をそのまま使う。

## わからんの森（Q&A）

```jsonc
// Category
{"id": 1, "name": "みんなの広場", "emoji": "🌳", "description": "", "question_count": 12, "unanswered_count": 2}
// Question
{"id": 3, "category": {"id": 1, "name": "…", "emoji": "🌳"}, "title": "…", "body": "…",
 "identity": "real", "display_name": null, "author": UserSummary | null, "is_mine": false,
 "answer_count": 2, "view_count": 8, "created_at": "...", "can_delete": false}
// Answer
{"id": 7, "question_id": 3, "body": "…", "identity": "real", "display_name": null,
 "author": UserSummary | null, "is_mine": false, "like_count": 2, "liked_by_me": false,
 "comments": [AnswerComment], "created_at": "...", "can_delete": false}
// AnswerComment
{"id": 9, "body": "…", "identity": "real", "display_name": null, "author": UserSummary | null,
 "is_mine": false, "created_at": "...", "can_delete": false}
```

| API | 内容 |
| --- | --- |
| `GET /api/forest` | → `{"categories": [Category], "unanswered": [Question]（古い順・10 件）, "recent": [Question]（20 件）, "urgency": "calm|soft|warm|hot"}` |
| `GET /api/forest/questions?category_id=&filter=unanswered|mine&before=` | → `{"questions", "next_before"}` |
| `POST /api/forest/questions` | `{"category_id", "title", "body", "identity"}` → `{"question"}` |
| `GET /api/forest/questions/{id}` | → `{"question", "answers": [Answer]}`（閲覧数を数える） |
| `DELETE /api/forest/questions/{id}` | 質問者・管理者 → `204` |
| `POST /api/forest/questions/{id}/answers` | `{"body", "identity"}` → `{"answer"}` |
| `DELETE /api/forest/answers/{id}` | → `204` |
| `PUT /api/forest/answers/{id}/like` / `DELETE` | → `{"answer"}` |
| `POST /api/forest/answers/{id}/comments` | `{"body", "identity"}` → `{"comment"}` |
| `DELETE /api/forest/answer-comments/{id}` | → `204` |

`urgency` は「他の人の未回答の質問のうち最も古いもの」の経過時間: 6 時間未満 `calm` / 24 時間未満 `soft`（ちょっと聞かれてるかも）/
72 時間未満 `warm`（数日 答え待ちです）/ それ以上 `hot`（長く答え待ちです）。

## バッジ・既読・右側の欄

| API | 内容 |
| --- | --- |
| `GET /api/badges` | → `{"notifications": 2, "forest_has_new": true, "forest_urgency": "soft", "commit_has_new": false, "announcements_unacked": 1, "channels_unread": 4}` |
| `POST /api/seen/{key}` | `key` = `home` / `forest` / `commit` / `channel-{id}` → `204`（その画面を見た） |
| `GET /api/highlights` | → 下記 |

```jsonc
{"members_today": [UserSummary],          // 今日ログイン・投稿した人（最大 12 人）
 "active_7d": 18,                          // 直近 1 週間でアクティブな人数
 "trending": [{"id": 10, "excerpt": "…", "display_name": "高橋 優子", "like_count": 5, "comment_count": 3}],
 "recent_reactions": [{"type": "like" | "comment", "actor": UserSummary | null,  // いいねは常に null
                       "display_name": "…" | null, "post_id": 10, "excerpt": "…", "created_at": "..."}]}
```

## 通知（追加）

`type` に `answer`（自分の質問に回答）/ `answer_comment`（自分の回答にコメント）/ `share` / `quote` を追加。
各通知に `"target": {"type": "post" | "question", "id": 10}` を追加（`post_id` は投稿のときだけ）。
匿名・部署名からのメンションやコメントは `actor: null`、`actor_name` に表示名。

## プロフィール

- `GET /api/users/{id}` → `{"user": UserSummary + {"email", "bio", "cover_url"}, "posts": [Post], "commits": [Post], "questions": [Question]}`（実名のものだけ）
- `PATCH /api/me` `{"bio", "nickname", "avatar_upload_id": "..." | null, "cover_upload_id": "..." | null}`
  - `nickname` は 1〜20 文字。空文字で削除。氏名と同じにはできない。

## 管理（追加）

| API | 内容 |
| --- | --- |
| `GET/POST /api/admin/forest-categories`, `PATCH /api/admin/forest-categories/{id}` | 森のカテゴリ `{"name", "emoji", "description", "position"}` |
| `GET /api/admin/insights` | 利用状況（日別の投稿・コメント・アクティブ人数、部署別、チャンネル別、しばらく見ていない人、盛り上がった投稿）と AI レポートの履歴 |
| `POST /api/admin/insights/generate` | AI で定性レポートを作る（API キー未設定なら `400 ai_not_configured`） |
| 設定 `PATCH /api/admin/settings` | `identity_department_enabled`, `identity_anonymous_enabled`, `watermark_mobile`（スマホで画面に名前の透かし）を追加 |
| チャンネル | `emoji` を追加 |
