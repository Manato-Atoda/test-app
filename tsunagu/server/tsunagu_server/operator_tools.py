"""サービス運営者向けの操作（企業の作成・デモデータ）。コマンドラインから使う。"""
from __future__ import annotations

import json
import sqlite3
from typing import Dict, List, Optional, Tuple

from . import passwords
from .accounts import COMPANY_CODE_RE, insert_user, issue_credentials, normalize_company_code, validate_user_fields
from .config import Config
from .db import DEFAULT_SETTINGS, audit, now
from .pdf import AccountNotice
from .web import ApiError

DEFAULT_CHANNELS = [
    # name, description, visibility, company_wide, post_policy, sort
    ("お知らせ", "会社からの公式なお知らせ（管理者のみ投稿）", "open", 1, "admins", 0),
    ("全社", "全員が参加する雑談・共有のチャンネル", "open", 1, "everyone", 1),
]


def create_company(db: sqlite3.Connection, cfg: Config, *, code: str, name: str, admin: Dict[str, str],
                   issue_via: str = "pdf") -> Tuple[int, int, AccountNotice]:
    """企業と最初の管理者を作り、管理者のアカウント通知（仮パスワード入り）を返す。"""
    code = normalize_company_code(code)
    if not COMPANY_CODE_RE.match(code):
        raise ApiError(400, "invalid_field", "企業コードは半角英数字3〜16文字にしてください")
    if not name.strip():
        raise ApiError(400, "required", "企業名を入力してください")
    if db.execute("SELECT 1 FROM companies WHERE code = ?", (code,)).fetchone():
        raise ApiError(409, "duplicate", "企業コード %s は既に使われています" % code)
    cur = db.execute("INSERT INTO companies (code, name, settings, created_at) VALUES (?, ?, ?, ?)",
                     (code, name.strip(), json.dumps(DEFAULT_SETTINGS, ensure_ascii=False), now()))
    company_id = int(cur.lastrowid)
    for ch_name, desc, visibility, wide, policy, sort in DEFAULT_CHANNELS:
        db.execute("INSERT INTO channels (company_id, name, description, visibility, company_wide, post_policy,"
                   " sort_order, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                   (company_id, ch_name, desc, visibility, wide, policy, sort, now()))
    fields = validate_user_fields(dict(admin, role="admin"))
    admin_id = insert_user(db, company_id, fields, None)
    audit(db, company_id=company_id, actor_id=None, action="company.created", detail={"code": code, "by": "cli"})
    company = db.execute("SELECT * FROM companies WHERE id = ?", (company_id,)).fetchone()
    user = db.execute("SELECT * FROM users WHERE id = ?", (admin_id,)).fetchone()
    notice = issue_credentials(db, cfg, company, user, method=issue_via, actor_id=None, ip=None)
    return company_id, admin_id, notice


# ------------------------------------------------------------------ デモデータ（開発用）

# 開発・動作確認用の仮パスワード。デモ企業の発行済みアカウントはすべてこれで初回ログインできる
# （初回ログイン時に新しいパスワードへの変更が必要）。本番のデータには絶対に使わないこと。
DEMO_COMPANY_CODE = "DEMO"
DEMO_TEMP_PASSWORD = "Demo-Start-2026"

DEMO_USERS: List[Dict[str, str]] = [
    {"employee_code": "E0001", "display_name": "佐藤 美咲", "department": "総務部", "title": "部長",
     "email": "misaki.sato@demo.example", "role": "admin"},
    {"employee_code": "E0002", "display_name": "鈴木 健太", "department": "開発部", "title": "エンジニア",
     "email": "kenta.suzuki@demo.example", "role": "member"},
    {"employee_code": "E0003", "display_name": "高橋 優子", "department": "営業部", "title": "主任",
     "email": "yuko.takahashi@demo.example", "role": "member"},
    {"employee_code": "E0004", "display_name": "田中 翔", "department": "開発部", "title": "デザイナー",
     "email": "", "role": "member"},
    {"employee_code": "E0005", "display_name": "伊藤 結衣", "department": "人事部", "title": "",
     "email": "yui.ito@demo.example", "role": "member"},
]


def seed_demo(db: sqlite3.Connection, cfg: Config) -> Optional[int]:
    """デモ企業を作る。既にあれば何もしない（None を返す）。"""
    if db.execute("SELECT 1 FROM companies WHERE code = ?", (DEMO_COMPANY_CODE,)).fetchone():
        return None
    admin = {k: v for k, v in DEMO_USERS[0].items() if k != "role"}
    company_id, admin_id, _ = create_company(db, cfg, code=DEMO_COMPANY_CODE, name="デモ株式会社", admin=admin,
                                             issue_via="cli")
    ids = {"E0001": admin_id}
    for u in DEMO_USERS[1:]:
        ids[u["employee_code"]] = insert_user(db, company_id, validate_user_fields(u), admin_id)

    # E0005 は「未発行」の例として残し、それ以外は既知の仮パスワードで発行済みにする
    ts = now()
    demo_hash = passwords.hash_password(DEMO_TEMP_PASSWORD)
    for code in ("E0001", "E0002", "E0003", "E0004"):
        db.execute("UPDATE users SET password_hash = ?, must_change_password = 1, temp_password_expires_at = ?,"
                   " credentials_issued_at = ?, credentials_issued_via = 'cli' WHERE id = ?",
                   (demo_hash, ts + 30 * 86400, ts, ids[code]))

    channels = {}
    for ch_name, desc, visibility, members in (
            ("開発部", "開発部の連絡・相談", "open", ["E0002", "E0004"]),
            ("営業部", "営業部の共有", "open", ["E0003"]),
            ("雑談", "業務以外の話題もどうぞ", "open", ["E0001", "E0002", "E0003", "E0004"]),
            ("経営企画", "経営企画メンバー限定", "private", ["E0001"])):
        cur = db.execute("INSERT INTO channels (company_id, name, description, visibility, created_by, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (company_id, ch_name, desc, visibility, admin_id, ts))
        channels[ch_name] = cur.lastrowid
        for code in members:
            db.execute("INSERT INTO channel_members (channel_id, user_id, joined_at) VALUES (?, ?, ?)",
                       (cur.lastrowid, ids[code], ts))
    for row in db.execute("SELECT id, name FROM channels WHERE company_id = ? AND company_wide = 1", (company_id,)):
        channels[row["name"]] = row["id"]

    def post(channel: str, author: str, body: str, minutes_ago: int, kind: str = "post", ack: bool = False) -> int:
        cur = db.execute("INSERT INTO posts (company_id, channel_id, author_id, body, kind, require_ack, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (company_id, channels[channel], ids[author], body, kind, int(ack), ts - minutes_ago * 60))
        return int(cur.lastrowid)

    p1 = post("お知らせ", "E0001",
              "【必読】社内SNS「つなぐ」の利用を開始します\n\n本日から、部署をまたいだ連絡や情報共有に「つなぐ」を使います。"
              "最初に「社内SNS 利用ガイドライン」を確認し、この投稿の「確認しました」を押してください。", 300,
              kind="announcement", ack=True)
    p2 = post("全社", "E0003", "今月の営業目標を達成しました！ご協力いただいた皆さん、ありがとうございました。", 180)
    p3 = post("開発部", "E0002",
              "@E0004 新しいログイン画面のデザイン案、確認しました。パスキーのボタンの位置だけ相談させてください。", 90)
    post("雑談", "E0004", "1階の自販機に新しいお茶が入っていました🍵", 30)
    post("経営企画", "E0001", "来期の計画は来週の会議で共有します（このチャンネルはメンバー限定です）。", 20)
    db.execute("INSERT INTO comments (company_id, post_id, author_id, body, created_at) VALUES (?, ?, ?, ?, ?)",
               (company_id, p3, ids["E0004"], "ありがとうございます。明日の午前に15分ほどお時間ください！", ts - 60 * 60))
    for post_id, code, key in ((p2, "E0001", "clap"), (p2, "E0002", "celebrate"), (p2, "E0004", "clap"),
                               (p3, "E0004", "eyes"), (p1, "E0002", "like")):
        db.execute("INSERT INTO reactions (post_id, user_id, reaction, created_at) VALUES (?, ?, ?, ?)",
                   (post_id, ids[code], key, ts))
    db.execute("INSERT INTO acks (post_id, user_id, created_at) VALUES (?, ?, ?)", (p1, ids["E0002"], ts))
    db.execute("INSERT INTO notifications (company_id, user_id, type, actor_id, post_id, created_at)"
               " VALUES (?, ?, 'mention', ?, ?, ?)", (company_id, ids["E0004"], ids["E0002"], p3, ts - 90 * 60))
    return company_id
