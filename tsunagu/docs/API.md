# つなぐ API 仕様（v1）

- ベース URL: 開発時 `http://localhost:8790`（`TSUNAGU_PUBLIC_URL` で変更）
- すべて JSON（UTF-8）。日時は ISO 8601 UTC（例 `2026-11-20T01:23:45Z`）。
- 認証: `Authorization: Bearer <token>`
- エラー: HTTP ステータス + `{"error": {"code": "invalid_credentials", "message": "日本語の説明", ...追加情報}}`
- ページング: 新しい順。レスポンスの `next_before` を次回の `?before=` に渡す（`null` なら終わり）。

## セッションの種類

| scope | 取得方法 | 使える API |
| --- | --- | --- |
| `password_change` | 仮パスワードでログイン（初回・再発行後） | `/api/auth/change-password`, `/api/auth/logout`, `/api/me`, `/api/meta` のみ。30 分で失効 |
| `full` | 通常ログイン / パスワード変更後 / パスキー | すべて（管理 API は `role=admin` のみ） |

`full` が必要な API を `password_change` で呼ぶと `403 password_change_required`。

## 共通オブジェクト

```jsonc
// UserSummary
{"id": 3, "display_name": "山田 花子", "employee_code": "E0003", "department": "営業部",
 "title": "主任", "avatar_color": 4, "role": "member", "status": "active"}

// Me（UserSummary に加えて）
{"email": "hanako@example.co.jp", "bio": "", "must_change_password": false,
 "passkey_count": 1, "last_login_at": "...", "guidelines_accepted_version": 1}

// Company
{"id": 1, "code": "DEMO", "name": "デモ株式会社", "guidelines": "…", "guidelines_version": 1}

// Post
{"id": 10, "channel": {"id": 1, "name": "全社"}, "author": UserSummary,
 "body": "本文（プレーンテキスト）", "kind": "post" | "announcement",
 "require_ack": false, "acked_by_me": false, "ack_count": 0,
 "reactions": [{"key": "like", "count": 2, "reacted_by_me": true}],
 "comment_count": 1, "created_at": "...", "edited_at": null,
 "can_edit": true, "can_delete": true}

// Comment
{"id": 5, "post_id": 10, "author": UserSummary, "body": "…", "created_at": "...",
 "hidden": false, "can_delete": true}

// Channel
{"id": 1, "name": "全社", "description": "", "visibility": "open" | "private",
 "company_wide": true, "post_policy": "everyone" | "admins", "is_member": true,
 "can_post": true, "member_count": 12, "archived": false}
```

リアクションの `key` は固定: `like`👍 `thanks`🙏 `clap`👏 `celebrate`🎉 `idea`💡 `eyes`👀

## 公開

### `GET /api/meta`
```json
{"service_name": "つなぐ", "version": "0.1.0",
 "password_policy": {"min_length": 8, "max_length": 128, "require_letter": true,
                     "require_digit": true, "require_symbol": false,
                     "allowed_symbols": "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"},
 "passkey": {"rp_id": "localhost", "login_url": "http://localhost:8790/passkey/login",
             "app_scheme": "tsunagu"}}
```
`password_policy` は既定値。企業ごとの値は `/api/auth/password-policy`（要セッション）で取得。

## 認証

### `POST /api/auth/login`
```json
{"company_code": "DEMO", "login_id": "E0001 または メールアドレス", "password": "…",
 "device": {"platform": "ios", "name": "iPhone"}}
```
- 成功（通常）: `{"status": "ok", "token": "…", "user": Me, "company": Company}`
- 成功（パスワード再設定が必要）: `{"status": "password_change_required", "token": "…(scope=password_change)", "user": Me, "company": Company}`
- 失敗:
  - `401 invalid_credentials`（企業コード・ID・パスワードのどれが違うかは返さない）
  - `423 account_locked` `{"retry_after_seconds": 840}`（既定: 5 回失敗で 15 分）
  - `403 account_suspended`（パスワードが正しい場合のみ返す）
  - `403 temp_password_expired`（仮パスワードの有効期限切れ。管理者に再発行を依頼）
  - `403 not_issued`（アカウント情報が未発行）
  - `429 rate_limited`

### `GET /api/auth/password-policy`（要セッション・password_change 可）
`/api/meta` の `password_policy` と同じ形で、ログイン中の企業の設定を返す。

### `POST /api/auth/change-password`（password_change 可）
```json
{"current_password": "仮パスワード", "new_password": "新しいパスワード"}
```
- 成功: `{"status": "ok", "token": "…(新しい full トークン)", "user": Me, "company": Company}`
  - 古いトークンを含め、この利用者の他のセッションはすべて失効する。
- 失敗: `401 invalid_current_password` / `400 password_policy` `{"details": ["8文字以上にしてください", ...]}`

パスワード規則: 8 文字以上 128 文字以下 / 英字と数字を必ず含む / 記号（半角）も使える / 空白・全角は不可 /
社員コードやメールアドレスを含めない / 直近 5 回と同じものは不可 /（企業設定で記号必須・最小文字数を上げられる）

### `POST /api/auth/logout` → `204`
### `POST /api/auth/logout-all` → `204`（自分の全端末のセッションを失効）

### パスキーでログイン（アプリ）
アプリはブラウザ（ASWebAuthenticationSession / Custom Tabs など）でサーバーのページを開き、結果をカスタム URL で受け取る。
PKCE と同じく、アプリが作った `code_verifier` の SHA-256（base64url）を `code_challenge` として渡す。

1. アプリ: `code_verifier`（43〜128 文字のランダム文字列）と `state` を作る
2. アプリ: ブラウザで開く
   `GET /passkey/login?company=DEMO&login_id=E0001&redirect_uri=tsunagu://auth&code_challenge=…&state=…`
   - `redirect_uri` に使えるのは `tsunagu://auth` / `tsunagu://passkey`、またはデスクトップ用の `http://localhost:<port>/…` / `http://127.0.0.1:<port>/…`
   - `login_id` は省略可（端末に保存されたパスキーから選ぶ）
3. ページで認証が済むと `redirect_uri?code=…&state=…` に戻る（失敗時は `?error=…&state=…`）
4. アプリ: `POST /api/auth/exchange`
   ```json
   {"code": "…", "code_verifier": "…", "device": {"platform": "ios", "name": "iPhone"}}
   ```
   → `{"status": "ok", "token": "…", "user": Me, "company": Company}`（コードは 2 分・1 回限り）

### パスキーでログイン（ブラウザ・管理コンソール）
- `POST /api/auth/passkey/options` `{"company_code": "DEMO", "login_id": "E0001"}` →
  `{"challenge_id": "…", "publicKey": {PublicKeyCredentialRequestOptions（バイナリは base64url）}}`
- `POST /api/auth/passkey/verify`
  ```json
  {"challenge_id": "…", "credential": {"id": "…", "rawId": "…", "type": "public-key",
    "response": {"clientDataJSON": "…", "authenticatorData": "…", "signature": "…", "userHandle": "…"}},
   "app_redirect": {"redirect_uri": "tsunagu://auth", "code_challenge": "…", "state": "…"}}
  ```
  - `app_redirect` あり: `{"status": "redirect", "redirect_url": "tsunagu://auth?code=…&state=…"}`
  - なし: `{"status": "ok", "token": "…", "user": Me, "company": Company}`

### パスキーの登録・管理（要 full）
- `GET /api/me/passkeys` → `{"passkeys": [{"id": 1, "name": "iPhone", "created_at": "…", "last_used_at": "…"}]}`
- `DELETE /api/me/passkeys/{id}` → `204`
- `POST /api/me/passkeys/ticket` → `{"ticket": "…", "register_url": "http://localhost:8790/passkey/register?ticket=…", "expires_at": "…"}`
  - アプリは `register_url` に `&redirect_uri=tsunagu://passkey&state=…&name=端末名` を付けてブラウザで開く。
    完了すると `tsunagu://passkey?status=ok&state=…`（失敗は `?error=…`）に戻る。チケットは 5 分・1 回限り。
- ブラウザ用: `POST /api/passkeys/register/options` `{"ticket": "…"}` または Bearer →
  `{"challenge_id": "…", "publicKey": {PublicKeyCredentialCreationOptions}}`
- `POST /api/passkeys/register/verify`
  `{"challenge_id": "…", "name": "MacBook", "credential": {"id", "rawId", "type", "response": {"clientDataJSON", "attestationObject", "transports"}}}`
  → `{"passkey": {...}}`

## 自分

- `GET /api/me` → `{"user": Me, "company": Company, "unread_notifications": 2}`（password_change 可）
- `PATCH /api/me` `{"bio": "…"}` → `{"user": Me}`（氏名・部署・役職は管理者が管理）
- `POST /api/me/accept-guidelines` `{"version": 1}` → `{"user": Me}`
- `GET /api/me/sessions` → `{"sessions": [{"id", "client", "auth_method", "created_at", "last_seen_at", "current": true}]}`
- `DELETE /api/me/sessions/{id}` → `204`

## SNS

- `GET /api/channels` → `{"channels": [Channel]}`（全社・公開・自分が入っている非公開）
- `GET /api/channels/{id}` → `{"channel": Channel}`
- `POST /api/channels/{id}/join` / `POST /api/channels/{id}/leave` → `{"channel": Channel}`（全社チャンネルは不可）
- `GET /api/feed?channel_id=&kind=announcement&before=&limit=20` → `{"posts": [Post], "next_before": 123}`
  - `channel_id` なし: 自分が参加しているチャンネル（全社含む）のタイムライン
  - `kind=announcement`: お知らせだけ
- `POST /api/posts` `{"channel_id": 1, "body": "…", "kind": "post"|"announcement", "require_ack": false}` → `{"post": Post}`
  - `announcement` と `require_ack` は管理者のみ。本文は 1〜4000 文字。
  - 本文中の `@社員コード` はメンションになり、本人に通知される。
- `GET /api/posts/{id}` → `{"post": Post, "comments": [Comment]}`
- `PATCH /api/posts/{id}` `{"body": "…"}` → `{"post": Post}`（投稿者のみ。編集履歴は監査用に保存）
- `DELETE /api/posts/{id}` → `204`（投稿者 / 管理者。データは監査用に保持）
- `POST /api/posts/{id}/comments` `{"body": "…"}` → `{"comment": Comment}`（1〜2000 文字）
- `DELETE /api/comments/{id}` → `204`
- `PUT /api/posts/{id}/reactions/{key}` / `DELETE /api/posts/{id}/reactions/{key}` → `{"post": Post}`
- `POST /api/posts/{id}/ack` → `{"post": Post}`（お知らせの「確認しました」）
- `GET /api/posts/{id}/acks` → `{"acked": [UserSummary], "not_acked": [UserSummary]}`（投稿者・管理者のみ）
- `POST /api/reports` `{"target_type": "post"|"comment", "target_id": 10, "reason": "…"}` → `{"report_id": 1}`
- `GET /api/notifications?before=` → `{"notifications": [{"id", "type": "comment"|"mention"|"announcement", "actor": UserSummary, "post_id", "excerpt", "created_at", "read": false}], "unread_count": 2, "next_before": null}`
- `POST /api/notifications/read-all` → `204` / `POST /api/notifications/{id}/read` → `204`
- `GET /api/directory?q=` → `{"users": [UserSummary + {"email", "bio"}]}`（在籍者のみ）
- `GET /api/users/{id}` → `{"user": UserSummary + {"email", "bio"}, "posts": [Post]}`
- `GET /api/search?q=` → `{"posts": [Post]}`（自分が見られる投稿のみ）

## 管理（role=admin）

| API | 内容 |
| --- | --- |
| `GET /api/admin/stats` | 人数・未発行・初回ログイン待ち・7 日間の投稿数・未対応の通報 |
| `GET /api/admin/users?q=&state=` | 社員一覧（`account_state`: `not_issued` / `pending_first_login` / `temp_expired` / `active` / `locked` / `suspended` / `retired`） |
| `POST /api/admin/users` | 社員を登録 `{"employee_code", "email", "display_name", "department", "title", "role"}` |
| `PATCH /api/admin/users/{id}` | 社員情報の変更 |
| `POST /api/admin/users/{id}/status` | `{"status": "active"|"suspended"|"retired"}`（停止・退職で全セッション失効） |
| `POST /api/admin/users/{id}/unlock` | ロック解除 |
| `POST /api/admin/users/{id}/revoke-sessions` | 強制ログアウト |
| `POST /api/admin/users/{id}/delete-passkeys` | パスキーをすべて削除 |
| `POST /api/admin/credentials` | **アカウント情報の発行** `{"user_ids": [..], "method": "email"|"pdf"}`。仮パスワードを新しく作り（既存のパスワードは無効）、`pdf` は PDF（1 人 1 ページ）を返し、`email` は `{"sent": [id], "skipped": [{"id", "reason"}]}` |
| `POST /api/admin/users/import` | CSV 一括登録 `{"csv": "employee_code,email,display_name,department,title,role\n…"}` |
| `GET /api/admin/users/export` | CSV（パスワード類は含まない） |
| `GET/POST /api/admin/channels`, `PATCH /api/admin/channels/{id}` | チャンネル管理 |
| `GET/POST /api/admin/channels/{id}/members`, `DELETE /api/admin/channels/{id}/members/{user_id}` | 非公開チャンネルのメンバー |
| `GET /api/admin/reports?status=open`, `POST /api/admin/reports/{id}/resolve` | 通報の対応 `{"action": "hide"|"dismiss"}` |
| `GET /api/admin/audit-logs?before=`, `GET /api/admin/audit-logs/export` | 監査ログ |
| `GET/PATCH /api/admin/settings` | パスワード規則・仮パスワード有効期限・ロック回数・セッション日数・ガイドライン |
| `GET /api/admin/mail` | メール送信履歴（開発モードでは本文も表示） |
