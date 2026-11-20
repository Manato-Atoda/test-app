"""SQLite のスキーマと接続。

すべての業務テーブルは company_id を持ち、問い合わせは必ず企業で絞り込む（テナント分離）。
時刻は UNIX 秒（UTC）で保存し、API では ISO 8601 で返す。
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE COLLATE NOCASE,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  settings TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  employee_code TEXT NOT NULL COLLATE NOCASE,
  email TEXT COLLATE NOCASE,
  display_name TEXT NOT NULL,
  department TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL DEFAULT '',
  bio TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'member',            -- admin | member
  status TEXT NOT NULL DEFAULT 'active',          -- active | suspended | retired
  password_hash TEXT,                             -- NULL = アカウント情報が未発行
  must_change_password INTEGER NOT NULL DEFAULT 1,
  temp_password_expires_at INTEGER,
  credentials_issued_at INTEGER,
  credentials_issued_via TEXT,                    -- email | pdf | cli
  password_changed_at INTEGER,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER,
  last_login_at INTEGER,
  guidelines_accepted_version INTEGER NOT NULL DEFAULT 0,
  user_handle TEXT NOT NULL UNIQUE,               -- パスキー用の不透明な ID
  avatar_color INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (company_id, employee_code)
);
CREATE UNIQUE INDEX IF NOT EXISTS users_company_email ON users(company_id, email) WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS password_history (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  scope TEXT NOT NULL,                            -- full | password_change
  auth_method TEXT NOT NULL,                      -- password | passkey
  client TEXT NOT NULL DEFAULT '',
  ip TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS passkeys (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  credential_id TEXT NOT NULL UNIQUE,
  public_key BLOB NOT NULL,
  alg INTEGER NOT NULL,
  sign_count INTEGER NOT NULL DEFAULT 0,
  transports TEXT NOT NULL DEFAULT '',
  aaguid TEXT,
  backed_up INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER
);

CREATE TABLE IF NOT EXISTS webauthn_challenges (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,                             -- register | login
  company_id INTEGER,
  user_id INTEGER,
  challenge TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE IF NOT EXISTS passkey_tickets (
  ticket_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE IF NOT EXISTS app_auth_codes (
  code_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_challenge TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE IF NOT EXISTS channels (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  visibility TEXT NOT NULL DEFAULT 'open',        -- open | private
  company_wide INTEGER NOT NULL DEFAULT 0,        -- 1 = 全員が自動で参加（退出不可）
  post_policy TEXT NOT NULL DEFAULT 'everyone',   -- everyone | admins
  archived INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 100,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS channel_members (
  channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (channel_id, user_id)
);

CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  channel_id INTEGER NOT NULL REFERENCES channels(id),
  author_id INTEGER NOT NULL REFERENCES users(id),
  body TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'post',              -- post | announcement
  require_ack INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  edited_at INTEGER,
  deleted_at INTEGER,                             -- 削除しても監査のため本文は残す
  deleted_by INTEGER,
  hidden_at INTEGER,                              -- 管理者による非表示
  hidden_by INTEGER,
  hidden_reason TEXT
);
CREATE INDEX IF NOT EXISTS posts_channel ON posts(company_id, channel_id, id);
CREATE INDEX IF NOT EXISTS posts_company ON posts(company_id, id);

CREATE TABLE IF NOT EXISTS post_revisions (
  id INTEGER PRIMARY KEY,
  post_id INTEGER NOT NULL REFERENCES posts(id),
  body TEXT NOT NULL,
  edited_by INTEGER NOT NULL,
  edited_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS comments (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  post_id INTEGER NOT NULL REFERENCES posts(id),
  author_id INTEGER NOT NULL REFERENCES users(id),
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  deleted_by INTEGER,
  hidden_at INTEGER,
  hidden_by INTEGER
);
CREATE INDEX IF NOT EXISTS comments_post ON comments(post_id, id);

CREATE TABLE IF NOT EXISTS reactions (
  post_id INTEGER NOT NULL REFERENCES posts(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  reaction TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id, reaction)
);

CREATE TABLE IF NOT EXISTS acks (
  post_id INTEGER NOT NULL REFERENCES posts(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  target_type TEXT NOT NULL,                      -- post | comment
  target_id INTEGER NOT NULL,
  reporter_id INTEGER NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',            -- open | resolved
  resolution TEXT,                                -- hide | dismiss
  resolved_by INTEGER,
  resolved_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,                             -- comment | mention | announcement
  actor_id INTEGER,
  post_id INTEGER,
  comment_id INTEGER,
  created_at INTEGER NOT NULL,
  read_at INTEGER
);
CREATE INDEX IF NOT EXISTS notifications_user ON notifications(user_id, id);

CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY,
  company_id INTEGER,
  actor_id INTEGER,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id INTEGER,
  detail TEXT NOT NULL DEFAULT '{}',
  ip TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS audit_company ON audit_logs(company_id, id);

CREATE TABLE IF NOT EXISTS mail_outbox (
  id INTEGER PRIMARY KEY,
  company_id INTEGER,
  to_addr TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL,                           -- outbox | sent | failed
  error TEXT,
  created_at INTEGER NOT NULL
);

-- ---------------------------------------------------------------- v2（M：Galaxia 寄せ）
CREATE TABLE IF NOT EXISTS likes (
  post_id INTEGER NOT NULL REFERENCES posts(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS comment_likes (
  comment_id INTEGER NOT NULL REFERENCES comments(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (comment_id, user_id)
);

CREATE TABLE IF NOT EXISTS bookmarks (
  post_id INTEGER NOT NULL REFERENCES posts(id),
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX IF NOT EXISTS bookmarks_user ON bookmarks(user_id, created_at);

CREATE TABLE IF NOT EXISTS post_views (
  post_id INTEGER NOT NULL REFERENCES posts(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS uploads (
  id TEXT PRIMARY KEY,                            -- 推測できないランダムな ID
  company_id INTEGER NOT NULL REFERENCES companies(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  mime TEXT NOT NULL,
  size INTEGER NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  path TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS drafts (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  identity TEXT NOT NULL DEFAULT 'real',
  channel_id INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 画面を最後に見た日時（home / forest / commit / channel-{id}）。新着の印を出すために使う
CREATE TABLE IF NOT EXISTS seen_marks (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  seen_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, key)
);

CREATE TABLE IF NOT EXISTS forest_categories (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  name TEXT NOT NULL,
  emoji TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL DEFAULT 100,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  category_id INTEGER NOT NULL REFERENCES forest_categories(id),
  author_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  identity TEXT NOT NULL DEFAULT 'real',
  display_name TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  deleted_by INTEGER
);
CREATE INDEX IF NOT EXISTS questions_company ON questions(company_id, id);

CREATE TABLE IF NOT EXISTS question_views (
  question_id INTEGER NOT NULL REFERENCES questions(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  PRIMARY KEY (question_id, user_id)
);

CREATE TABLE IF NOT EXISTS answers (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  question_id INTEGER NOT NULL REFERENCES questions(id),
  author_id INTEGER NOT NULL REFERENCES users(id),
  body TEXT NOT NULL,
  identity TEXT NOT NULL DEFAULT 'real',
  display_name TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  deleted_by INTEGER
);
CREATE INDEX IF NOT EXISTS answers_question ON answers(question_id, id);

CREATE TABLE IF NOT EXISTS answer_likes (
  answer_id INTEGER NOT NULL REFERENCES answers(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (answer_id, user_id)
);

CREATE TABLE IF NOT EXISTS answer_comments (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  answer_id INTEGER NOT NULL REFERENCES answers(id),
  author_id INTEGER NOT NULL REFERENCES users(id),
  body TEXT NOT NULL,
  identity TEXT NOT NULL DEFAULT 'real',
  display_name TEXT,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER,
  deleted_by INTEGER
);

CREATE TABLE IF NOT EXISTS insight_reports (
  id INTEGER PRIMARY KEY,
  company_id INTEGER NOT NULL REFERENCES companies(id),
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  content TEXT NOT NULL,
  input_tokens INTEGER,
  output_tokens INTEGER,
  created_by INTEGER,
  created_at INTEGER NOT NULL
);
"""

# 既存のテーブルに足す列（古いデータベースもそのまま使えるように、起動時に足りない列を追加する）
V2_COLUMNS = {
    "users": [("nickname", "TEXT"), ("avatar_upload", "TEXT"), ("cover_upload", "TEXT")],
    "channels": [("emoji", "TEXT"), ("system_kind", "TEXT")],   # system_kind = 'commit'（COMMIT 置き場）
    "posts": [("identity", "TEXT NOT NULL DEFAULT 'real'"), ("display_name", "TEXT"),
              ("images", "TEXT NOT NULL DEFAULT '[]'"), ("quote_of", "INTEGER")],
    "comments": [("identity", "TEXT NOT NULL DEFAULT 'real'"), ("display_name", "TEXT"),
                 ("is_quick", "INTEGER NOT NULL DEFAULT 0"), ("edited_at", "INTEGER")],
    "notifications": [("question_id", "INTEGER"), ("answer_id", "INTEGER"), ("actor_name", "TEXT")],
}

DEFAULT_GUIDELINES = """社内SNS 利用ガイドライン

1. 業務に関わる情報共有と、社員どうしのコミュニケーションのための場です。
2. 顧客情報・個人情報・社外秘の資料（契約内容、未公開の数値など）は投稿しないでください。
3. 誹謗中傷・ハラスメント・差別にあたる発言は禁止です。
4. 画面の撮影や転送などで、投稿内容を社外へ持ち出さないでください。
5. 投稿・コメントは管理者が確認し、規程に反するものは非表示にすることがあります。
   また、利用の記録は監査のために保存されます。
6. 部署名・匿名（あだ名）での投稿も、ほかの人と同じルールが適用されます。
   通報があった場合、管理者は対応のために投稿者を確認できます。
7. 不適切な投稿を見つけたら、投稿のメニューから「通報」してください。"""

DEFAULT_SETTINGS: Dict[str, Any] = {
    "password_min_length": 8,
    "password_require_symbol": False,
    "temp_password_ttl_hours": 72,
    "lockout_threshold": 5,
    "lockout_minutes": 15,
    "session_days": 30,
    "guidelines": DEFAULT_GUIDELINES,
    "guidelines_version": 1,
    # v2: 発信者の切り替え（部署名・匿名）と、スマホでの透かし
    "identity_department_enabled": True,
    "identity_anonymous_enabled": True,
    "watermark_mobile": False,
}

QUICK_COMMENTS = [
    {"emoji": "👏", "text": "ナイス！"}, {"emoji": "🙌", "text": "お疲れさまです"}, {"emoji": "🔥", "text": "最高！"},
    {"emoji": "💡", "text": "参考になります"}, {"emoji": "✨", "text": "いいですね"},
    {"emoji": "💪", "text": "がんばってください"}, {"emoji": "🎉", "text": "おめでとうございます"},
    {"emoji": "🤝", "text": "ありがとうございます"}, {"emoji": "👀", "text": "気になる"}, {"emoji": "🍵", "text": "お疲れさま"},
]

DEFAULT_FOREST_CATEGORIES = [
    ("みんなの広場", "🌳", "どこに聞けばいいかわからないことは、まずここへ"),
    ("営業", "💼", ""), ("クリエイティブ", "🎨", ""), ("エンジニア", "💻", ""),
    ("バックオフィス", "📋", "経費・勤怠・社内手続きなど"), ("アルバイト", "🎒", ""),
]

JST = timezone(timedelta(hours=9))


def now() -> int:
    return int(time.time())


def iso(ts: Optional[int]) -> Optional[str]:
    if ts is None:
        return None
    return datetime.fromtimestamp(int(ts), tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


_WEEKDAYS = "月火水木金土日"


def jp_datetime(ts: int, with_time: bool = True) -> str:
    d = datetime.fromtimestamp(int(ts), tz=JST)
    text = "%d年%d月%d日(%s)" % (d.year, d.month, d.day, _WEEKDAYS[d.weekday()])
    return text + (" %02d:%02d" % (d.hour, d.minute) if with_time else "")


def connect(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 15000")
    return conn


def init_db(path: str) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    conn = connect(path)
    try:
        conn.execute("PRAGMA journal_mode = WAL")
        conn.executescript(SCHEMA)
        migrate(conn)
        conn.commit()
    finally:
        conn.close()


def company_settings(company: sqlite3.Row) -> Dict[str, Any]:
    settings = dict(DEFAULT_SETTINGS)
    try:
        settings.update(json.loads(company["settings"] or "{}"))
    except ValueError:
        pass
    return settings


def audit(conn: sqlite3.Connection, *, company_id: Optional[int], actor_id: Optional[int], action: str,
          target_type: Optional[str] = None, target_id: Optional[int] = None,
          detail: Optional[Dict[str, Any]] = None, ip: Optional[str] = None) -> None:
    conn.execute(
        "INSERT INTO audit_logs (company_id, actor_id, action, target_type, target_id, detail, ip, created_at)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (company_id, actor_id, action, target_type, target_id,
         json.dumps(detail or {}, ensure_ascii=False), ip, now()))


def migrate(conn: sqlite3.Connection) -> None:
    """古いデータベースを v2 の形にそろえる（何度実行しても同じ結果になる）。"""
    for table, columns in V2_COLUMNS.items():
        existing = {r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)}
        for name, decl in columns:
            if name not in existing:
                conn.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, name, decl))
    # v1 の 6 種類のリアクションは、ハートのいいねに移す（1 人 1 回）
    conn.execute("INSERT OR IGNORE INTO likes (post_id, user_id, created_at)"
                 " SELECT post_id, user_id, MIN(created_at) FROM reactions GROUP BY post_id, user_id")
    conn.execute("DELETE FROM reactions")
    for row in conn.execute("SELECT id FROM companies").fetchall():
        ensure_company_defaults(conn, row[0])


def ensure_company_defaults(conn: sqlite3.Connection, company_id: int) -> None:
    """企業ごとに必要なもの（COMMIT 置き場のチャンネル・森のカテゴリ）がなければ作る。"""
    if not conn.execute("SELECT 1 FROM channels WHERE company_id = ? AND system_kind = 'commit'",
                        (company_id,)).fetchone():
        conn.execute("INSERT INTO channels (company_id, name, description, visibility, company_wide, post_policy,"
                     " sort_order, system_kind, emoji, created_at)"
                     " VALUES (?, ?, 'COMMIT（宣言）の置き場。一覧には出ない', 'open', 1, 'everyone', 999, 'commit', '🚩', ?)",
                     (company_id, "__commit__", now()))
    if not conn.execute("SELECT 1 FROM forest_categories WHERE company_id = ?", (company_id,)).fetchone():
        for position, (name, emoji, desc) in enumerate(DEFAULT_FOREST_CATEGORIES):
            conn.execute("INSERT INTO forest_categories (company_id, name, emoji, description, position, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (company_id, name, emoji, desc, position, now()))


def get_seen(conn: sqlite3.Connection, user_id: int, key: str) -> int:
    row = conn.execute("SELECT seen_at FROM seen_marks WHERE user_id = ? AND key = ?", (user_id, key)).fetchone()
    return int(row[0]) if row else 0


def mark_seen(conn: sqlite3.Connection, user_id: int, key: str) -> None:
    conn.execute("INSERT INTO seen_marks (user_id, key, seen_at) VALUES (?, ?, ?)"
                 " ON CONFLICT(user_id, key) DO UPDATE SET seen_at = excluded.seen_at", (user_id, key, now()))
