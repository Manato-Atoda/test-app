"""アカウントまわりの共通処理（表示用の整形・セッション・アカウント情報の発行）。"""
from __future__ import annotations

import hashlib
import json
import re
import secrets
import sqlite3
from typing import Any, Dict, List, Optional, Tuple

from . import passwords
from .config import Config
from .db import audit, company_settings, iso, jp_datetime, now
from .mailer import send_mail
from .pdf import AccountNotice
from .web import ApiError

COMPANY_CODE_RE = re.compile(r"^[A-Za-z0-9]{3,16}$")
EMPLOYEE_CODE_RE = re.compile(r"^[A-Za-z0-9._-]{1,32}$")
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$")
ROLES = ("admin", "member")
STATUSES = ("active", "suspended", "retired")
PASSWORD_CHANGE_TTL = 30 * 60


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ------------------------------------------------------------------ 表示用

def user_summary(u: sqlite3.Row) -> Dict[str, Any]:
    return {
        "id": u["id"],
        "display_name": u["display_name"],
        "employee_code": u["employee_code"],
        "department": u["department"],
        "title": u["title"],
        "avatar_color": u["avatar_color"],
        "role": u["role"],
        "status": u["status"],
    }


def user_profile(u: sqlite3.Row) -> Dict[str, Any]:
    data = user_summary(u)
    data.update({"email": u["email"], "bio": u["bio"]})
    return data


def me_json(db: sqlite3.Connection, u: sqlite3.Row) -> Dict[str, Any]:
    data = user_profile(u)
    count = db.execute("SELECT COUNT(*) FROM passkeys WHERE user_id = ?", (u["id"],)).fetchone()[0]
    data.update({
        "must_change_password": bool(u["must_change_password"]),
        "passkey_count": count,
        "last_login_at": iso(u["last_login_at"]),
        "guidelines_accepted_version": u["guidelines_accepted_version"],
    })
    return data


def company_json(c: sqlite3.Row) -> Dict[str, Any]:
    settings = company_settings(c)
    return {
        "id": c["id"],
        "code": c["code"],
        "name": c["name"],
        "guidelines": settings["guidelines"],
        "guidelines_version": settings["guidelines_version"],
    }


def account_state(u: sqlite3.Row, ts: Optional[int] = None) -> str:
    ts = now() if ts is None else ts
    if u["status"] != "active":
        return u["status"]
    if not u["password_hash"]:
        return "not_issued"
    if u["locked_until"] and u["locked_until"] > ts:
        return "locked"
    if u["must_change_password"]:
        if u["temp_password_expires_at"] and u["temp_password_expires_at"] < ts:
            return "temp_expired"
        return "pending_first_login"
    return "active"


# ------------------------------------------------------------------ 入力チェック

def normalize_company_code(code: str) -> str:
    return code.strip().upper()


def validate_user_fields(data: Dict[str, Any], *, partial: bool = False) -> Dict[str, Any]:
    """管理者が入力した社員情報をチェックして整形する。"""
    out: Dict[str, Any] = {}

    def text(name: str, label: str, max_len: int, required: bool = False) -> None:
        if partial and name not in data:
            return
        value = data.get(name)
        value = "" if value is None else value
        if not isinstance(value, str):
            raise ApiError(400, "invalid_field", "%sの形式が正しくありません" % label, field=name)
        value = value.strip()
        if required and not value:
            raise ApiError(400, "required", "%sを入力してください" % label, field=name)
        if len(value) > max_len:
            raise ApiError(400, "too_long", "%sは%d文字以内にしてください" % (label, max_len), field=name)
        out[name] = value

    text("employee_code", "社員コード", 32, required=True)
    text("display_name", "氏名", 60, required=True)
    text("department", "部署", 60)
    text("title", "役職", 60)
    text("email", "メールアドレス", 254)
    if "employee_code" in out and not EMPLOYEE_CODE_RE.match(out["employee_code"]):
        raise ApiError(400, "invalid_field", "社員コードは半角英数字と . _ - で32文字以内にしてください",
                       field="employee_code")
    if "email" in out:
        out["email"] = out["email"].lower() or None
        if out["email"] and not EMAIL_RE.match(out["email"]):
            raise ApiError(400, "invalid_field", "メールアドレスの形式が正しくありません", field="email")
    if not partial or "role" in data:
        role = data.get("role") or "member"
        if role not in ROLES:
            raise ApiError(400, "invalid_field", "権限が正しくありません", field="role")
        out["role"] = role
    return out


def find_user_by_login_id(db: sqlite3.Connection, company_id: int, login_id: str) -> Optional[sqlite3.Row]:
    login_id = login_id.strip()
    if not login_id:
        return None
    if "@" in login_id:
        return db.execute("SELECT * FROM users WHERE company_id = ? AND email = ?",
                          (company_id, login_id.lower())).fetchone()
    return db.execute("SELECT * FROM users WHERE company_id = ? AND employee_code = ?",
                      (company_id, login_id)).fetchone()


def insert_user(db: sqlite3.Connection, company_id: int, fields: Dict[str, Any], created_by: Optional[int]) -> int:
    dup = db.execute("SELECT 1 FROM users WHERE company_id = ? AND employee_code = ?",
                     (company_id, fields["employee_code"])).fetchone()
    if dup:
        raise ApiError(409, "duplicate_employee_code", "社員コード %s は既に登録されています" % fields["employee_code"],
                       field="employee_code")
    if fields.get("email"):
        dup = db.execute("SELECT 1 FROM users WHERE company_id = ? AND email = ?",
                         (company_id, fields["email"])).fetchone()
        if dup:
            raise ApiError(409, "duplicate_email", "メールアドレス %s は既に登録されています" % fields["email"],
                           field="email")
    ts = now()
    cur = db.execute(
        "INSERT INTO users (company_id, employee_code, email, display_name, department, title, role,"
        " user_handle, avatar_color, created_by, created_at, updated_at)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (company_id, fields["employee_code"], fields.get("email"), fields["display_name"],
         fields.get("department", ""), fields.get("title", ""), fields.get("role", "member"),
         secrets.token_urlsafe(32), secrets.randbelow(8), created_by, ts, ts))
    return int(cur.lastrowid)


# ------------------------------------------------------------------ セッション

def device_label(device: Any, user_agent: str = "") -> str:
    names = {"ios": "iOS", "android": "Android", "macos": "Mac", "windows": "Windows", "web": "Web", "linux": "Linux"}
    if isinstance(device, dict):
        platform = names.get(str(device.get("platform", "")).lower(), "")
        name = str(device.get("name", ""))[:60]
        label = " · ".join(p for p in (platform, name) if p)
        if label:
            return label
    if user_agent:
        return "Web ブラウザ"
    return "不明な端末"


def create_session(db: sqlite3.Connection, user: sqlite3.Row, company: sqlite3.Row, *, scope: str,
                   method: str, client: str, ip: str) -> str:
    token = secrets.token_urlsafe(32)
    ts = now()
    if scope == "full":
        ttl = int(company_settings(company)["session_days"]) * 86400
    else:
        ttl = PASSWORD_CHANGE_TTL
    db.execute("INSERT INTO sessions (user_id, token_hash, scope, auth_method, client, ip, created_at,"
               " last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
               (user["id"], hash_token(token), scope, method, client, ip, ts, ts, ts + ttl))
    return token


def revoke_sessions(db: sqlite3.Connection, user_id: int, except_session_id: Optional[int] = None) -> int:
    if except_session_id is None:
        cur = db.execute("UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL",
                         (now(), user_id))
    else:
        cur = db.execute("UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL AND id != ?",
                         (now(), user_id, except_session_id))
    return cur.rowcount


def login_payload(db: sqlite3.Connection, user_id: int, company: sqlite3.Row, token: str, status: str) -> Dict[str, Any]:
    user = db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return {"status": status, "token": token, "user": me_json(db, user), "company": company_json(company)}


# ------------------------------------------------------------------ アカウント情報の発行

def _mail_text(n: AccountNotice, password_text: str) -> str:
    rule = "%d文字以上・英字と数字を含む。記号も使えます" % n.min_length
    if n.require_symbol:
        rule = "%d文字以上・英字と数字と記号を含む" % n.min_length
    email_line = n.email or "（登録なし）"
    return (
        "{name} 様\n\n"
        "{company} の社内SNS「{service}」のアカウントを発行しました。\n"
        "下記の情報でログインしてください。\n\n"
        "■ ログイン情報\n"
        "企業コード　　：{company_code}\n"
        "社員コード　　：{employee_code}\n"
        "メールアドレス：{email}\n"
        "仮パスワード　：{password}\n"
        "有効期限　　　：{expires} まで\n\n"
        "■ ログイン手順\n"
        "1. アプリ「{service}」を開く（iPhone / Android / Mac / Windows）\n"
        "2. 企業コード、社員コード（またはメールアドレス）、仮パスワードを入力してログイン\n"
        "3. 新しいパスワードを設定（{rule}）\n"
        "4. 設定画面でパスキーを登録すると、次回から指紋・顔認証でログインできます\n\n"
        "■ ご注意\n"
        "・このメールは本人以外に転送しないでください。\n"
        "・パスワードを設定したら、このメールは削除してください。\n"
        "・有効期限を過ぎた場合は、社内の管理者に再発行を依頼してください。\n"
        "・心当たりがない場合は、社内の管理者にご連絡ください。\n\n"
        "接続先：{url}\n"
        "--\n"
        "{company} 社内SNS管理者（このメールは送信専用です）\n"
    ).format(name=n.display_name, company=n.company_name, service=n.service_name, company_code=n.company_code,
             employee_code=n.employee_code, email=email_line, password=password_text, expires=n.expires_at_text,
             rule=rule, url=n.login_url)


def issue_credentials(db: sqlite3.Connection, cfg: Config, company: sqlite3.Row, user: sqlite3.Row, *,
                      method: str, actor_id: Optional[int], ip: Optional[str]) -> AccountNotice:
    """仮パスワードを新しく作って保存し、通知内容を返す。

    仮パスワードはハッシュだけを保存する。平文はこの関数の戻り値（PDF / メール）にしか現れない。
    既存のパスワードは無効になり、ログイン中のセッションも失効させる。
    """
    settings = company_settings(company)
    temp = passwords.generate_temporary_password()
    ts = now()
    expires = ts + int(settings["temp_password_ttl_hours"]) * 3600
    db.execute(
        "UPDATE users SET password_hash = ?, must_change_password = 1, temp_password_expires_at = ?,"
        " credentials_issued_at = ?, credentials_issued_via = ?, failed_attempts = 0, locked_until = NULL,"
        " updated_at = ? WHERE id = ?",
        (passwords.hash_password(temp), expires, ts, method, ts, user["id"]))
    revoke_sessions(db, user["id"])
    audit(db, company_id=company["id"], actor_id=actor_id, action="admin.credentials.issued",
          target_type="user", target_id=user["id"],
          detail={"method": method, "employee_code": user["employee_code"]}, ip=ip)
    return AccountNotice(
        company_name=company["name"], company_code=company["code"], display_name=user["display_name"],
        department=user["department"], employee_code=user["employee_code"], email=user["email"],
        temporary_password=temp, expires_at_text=jp_datetime(expires), issued_at_text=jp_datetime(ts, False),
        login_url=cfg.public_url, min_length=passwords.policy_from_settings(settings)["min_length"],
        require_symbol=bool(settings["password_require_symbol"]))


def send_credentials_mail(db: sqlite3.Connection, cfg: Config, company_id: int, notice: AccountNotice) -> bool:
    assert notice.email
    subject = "【つなぐ】アカウント発行のお知らせ（%s）" % notice.company_name
    return send_mail(db, cfg, company_id=company_id, to=notice.email, subject=subject,
                     body=_mail_text(notice, notice.temporary_password),
                     redacted_body=_mail_text(notice, "（送信履歴には表示しません）"))


def issuable(user: sqlite3.Row) -> Tuple[bool, str]:
    if user["status"] != "active":
        return False, "利用停止中または退職済みです"
    return True, ""


def load_settings_json(raw: str) -> Dict[str, Any]:
    try:
        return json.loads(raw or "{}")
    except ValueError:
        return {}


def users_by_ids(db: sqlite3.Connection, company_id: int, ids: List[int]) -> List[sqlite3.Row]:
    if not ids:
        return []
    marks = ",".join("?" * len(ids))
    return db.execute("SELECT * FROM users WHERE company_id = ? AND id IN (%s) ORDER BY employee_code" % marks,
                      [company_id] + list(ids)).fetchall()
