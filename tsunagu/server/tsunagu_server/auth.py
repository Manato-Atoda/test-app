"""ログイン・パスワード再設定・パスキー（WebAuthn）・自分のセッション。"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import sqlite3
from typing import Any, Dict, Optional
from urllib.parse import urlencode, urlparse

from . import passwords, webauthn
from .accounts import (company_json, create_session, device_label, find_user_by_login_id, hash_token,
                       login_payload, me_json, normalize_company_code, revoke_sessions)
from .db import audit, company_settings, iso, now
from .web import ApiError, Ctx, Response, Router

router = Router()

GENERIC_LOGIN_ERROR = "企業コード、社員コード／メールアドレス、またはパスワードが正しくありません"
CHALLENGE_TTL = 5 * 60
TICKET_TTL = 5 * 60
APP_CODE_TTL = 2 * 60


def _company_by_code(db: sqlite3.Connection, code: str) -> Optional[sqlite3.Row]:
    if not code:
        return None
    return db.execute("SELECT * FROM companies WHERE code = ? AND status = 'active'",
                      (normalize_company_code(code),)).fetchone()


def _check_login_allowed(ctx: Ctx, user: sqlite3.Row, company: sqlite3.Row) -> None:
    """パスワード（またはパスキー）が正しいと確認できた後の状態チェック。"""
    if user["status"] != "active":
        audit(ctx.db, company_id=company["id"], actor_id=user["id"], action="auth.login.blocked",
              detail={"reason": user["status"]}, ip=ctx.req.ip)
        ctx.db.commit()
        raise ApiError(403, "account_suspended", "このアカウントは利用停止中です。管理者にお問い合わせください")


def _record_success(ctx: Ctx, user: sqlite3.Row, company: sqlite3.Row, method: str) -> None:
    ctx.db.execute("UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login_at = ? WHERE id = ?",
                   (now(), user["id"]))
    audit(ctx.db, company_id=company["id"], actor_id=user["id"], action="auth.login.success",
          detail={"method": method}, ip=ctx.req.ip)


# ------------------------------------------------------------------ 公開

@router.route("GET", "/api/meta", auth="public")
def meta(ctx: Ctx) -> Response:
    return Response.json({
        "service_name": "つなぐ",
        "version": "0.1.0",
        "password_policy": passwords.policy_from_settings({}),
        "passkey": {"rp_id": ctx.cfg.rp_id, "login_url": ctx.cfg.public_url + "/passkey/login",
                    "app_scheme": ctx.cfg.app_scheme},
    })


@router.route("POST", "/api/auth/login", auth="public")
def login(ctx: Ctx) -> Response:
    req = ctx.req
    ctx.app.rate.check("login:" + req.ip, limit=30, window=300)
    company_code = req.str_field("company_code", label="企業コード", max_len=32)
    login_id = req.str_field("login_id", label="社員コードまたはメールアドレス", max_len=254)
    password = req.json().get("password")
    if not isinstance(password, str) or not password:
        raise ApiError(400, "required", "パスワードを入力してください", field="password")
    if len(password) > 256:
        raise ApiError(401, "invalid_credentials", GENERIC_LOGIN_ERROR)

    company = _company_by_code(ctx.db, company_code)
    user = find_user_by_login_id(ctx.db, company["id"], login_id) if company else None
    ts = now()

    if user is not None and user["locked_until"] and user["locked_until"] > ts:
        passwords.verify_password(password, None)  # 時間をそろえる
        raise ApiError(423, "account_locked",
                       "ログインに続けて失敗したため、一時的にロックしています。しばらく待ってからやり直してください",
                       retry_after_seconds=int(user["locked_until"] - ts))

    if user is None or not passwords.verify_password(password, user["password_hash"]):
        if company is not None:
            detail: Dict[str, Any] = {"login_id": login_id[:64]}
            if user is not None:
                settings = company_settings(company)
                failures = int(user["failed_attempts"]) + 1
                if failures >= int(settings["lockout_threshold"]):
                    ctx.db.execute("UPDATE users SET failed_attempts = 0, locked_until = ? WHERE id = ?",
                                   (ts + int(settings["lockout_minutes"]) * 60, user["id"]))
                    detail["locked"] = True
                else:
                    ctx.db.execute("UPDATE users SET failed_attempts = ? WHERE id = ?", (failures, user["id"]))
            audit(ctx.db, company_id=company["id"], actor_id=user["id"] if user else None,
                  action="auth.login.failure", detail=detail, ip=req.ip)
            ctx.db.commit()
        raise ApiError(401, "invalid_credentials", GENERIC_LOGIN_ERROR)

    assert company is not None
    _check_login_allowed(ctx, user, company)
    if user["must_change_password"] and user["temp_password_expires_at"] and user["temp_password_expires_at"] < ts:
        audit(ctx.db, company_id=company["id"], actor_id=user["id"], action="auth.login.blocked",
              detail={"reason": "temp_password_expired"}, ip=req.ip)
        ctx.db.commit()
        raise ApiError(403, "temp_password_expired",
                       "仮パスワードの有効期限が切れています。管理者に再発行を依頼してください")

    _record_success(ctx, user, company, "password")
    client = device_label(req.json().get("device"), req.headers.get("user-agent", ""))
    if user["must_change_password"]:
        token = create_session(ctx.db, user, company, scope="password_change", method="password",
                               client=client, ip=req.ip)
        return Response.json(login_payload(ctx.db, user["id"], company, token, "password_change_required"))
    token = create_session(ctx.db, user, company, scope="full", method="password", client=client, ip=req.ip)
    return Response.json(login_payload(ctx.db, user["id"], company, token, "ok"))


# ------------------------------------------------------------------ パスワード

@router.route("GET", "/api/auth/password-policy", auth="limited")
def password_policy(ctx: Ctx) -> Response:
    return Response.json(passwords.policy_from_settings(company_settings(ctx.company)))


@router.route("POST", "/api/auth/change-password", auth="limited")
def change_password(ctx: Ctx) -> Response:
    req = ctx.req
    ctx.app.rate.check("pwchange:%d" % ctx.uid, limit=10, window=300)
    current = req.json().get("current_password")
    new = req.json().get("new_password")
    if not isinstance(current, str) or not isinstance(new, str) or not current or not new:
        raise ApiError(400, "required", "現在のパスワードと新しいパスワードを入力してください")
    user = ctx.user
    assert user is not None and ctx.company is not None
    if not passwords.verify_password(current, user["password_hash"]):
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="auth.password.change_failed",
              detail={"reason": "wrong_current"}, ip=req.ip)
        ctx.db.commit()
        raise ApiError(401, "invalid_current_password", "現在のパスワードが正しくありません")
    policy = passwords.policy_from_settings(company_settings(ctx.company))
    problems = passwords.check_policy(new, policy, employee_code=user["employee_code"], email=user["email"])
    history = [r[0] for r in ctx.db.execute(
        "SELECT password_hash FROM password_history WHERE user_id = ? ORDER BY id DESC LIMIT ?",
        (ctx.uid, passwords.HISTORY_SIZE)).fetchall()]
    if not problems and (new == current or passwords.reused(new, history + [user["password_hash"]])):
        problems.append("以前に使ったパスワードや仮パスワードは使えません")
    if problems:
        raise ApiError(400, "password_policy", problems[0], details=problems)

    ts = now()
    new_hash = passwords.hash_password(new)
    ctx.db.execute("UPDATE users SET password_hash = ?, must_change_password = 0, temp_password_expires_at = NULL,"
                   " password_changed_at = ?, updated_at = ? WHERE id = ?", (new_hash, ts, ts, ctx.uid))
    ctx.db.execute("INSERT INTO password_history (user_id, password_hash, created_at) VALUES (?, ?, ?)",
                   (ctx.uid, new_hash, ts))
    ctx.db.execute("DELETE FROM password_history WHERE user_id = ? AND id NOT IN (SELECT id FROM password_history"
                   " WHERE user_id = ? ORDER BY id DESC LIMIT ?)", (ctx.uid, ctx.uid, passwords.HISTORY_SIZE))
    revoke_sessions(ctx.db, ctx.uid)
    assert ctx.session is not None
    token = create_session(ctx.db, user, ctx.company, scope="full", method=ctx.session["auth_method"],
                           client=ctx.session["client"], ip=req.ip)
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="auth.password.changed",
          detail={"first_login": bool(user["must_change_password"])}, ip=req.ip)
    return Response.json(login_payload(ctx.db, ctx.uid, ctx.company, token, "ok"))


@router.route("POST", "/api/auth/logout", auth="limited")
def logout(ctx: Ctx) -> Response:
    assert ctx.session is not None
    ctx.db.execute("UPDATE sessions SET revoked_at = ? WHERE id = ?", (now(), ctx.session["id"]))
    return Response.empty()


@router.route("POST", "/api/auth/logout-all", auth="user")
def logout_all(ctx: Ctx) -> Response:
    revoke_sessions(ctx.db, ctx.uid)
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="auth.logout_all", ip=ctx.req.ip)
    return Response.empty()


# ------------------------------------------------------------------ 自分

@router.route("GET", "/api/me", auth="limited")
def get_me(ctx: Ctx) -> Response:
    unread = ctx.db.execute("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at IS NULL",
                            (ctx.uid,)).fetchone()[0]
    assert ctx.user is not None and ctx.company is not None
    return Response.json({"user": me_json(ctx.db, ctx.user), "company": company_json(ctx.company),
                          "unread_notifications": unread})


@router.route("PATCH", "/api/me", auth="user")
def patch_me(ctx: Ctx) -> Response:
    data = ctx.req.json()
    if "bio" in data:
        bio = ctx.req.str_field("bio", required=False, max_len=300, label="自己紹介")
        ctx.db.execute("UPDATE users SET bio = ?, updated_at = ? WHERE id = ?", (bio, now(), ctx.uid))
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (ctx.uid,)).fetchone()
    return Response.json({"user": me_json(ctx.db, user)})


@router.route("POST", "/api/me/accept-guidelines", auth="user")
def accept_guidelines(ctx: Ctx) -> Response:
    version = ctx.req.json().get("version")
    current = int(company_settings(ctx.company)["guidelines_version"])
    if version != current:
        raise ApiError(409, "guidelines_changed", "ガイドラインが更新されています。最新の内容を確認してください")
    ctx.db.execute("UPDATE users SET guidelines_accepted_version = ? WHERE id = ?", (current, ctx.uid))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="user.guidelines.accepted",
          detail={"version": current}, ip=ctx.req.ip)
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (ctx.uid,)).fetchone()
    return Response.json({"user": me_json(ctx.db, user)})


@router.route("GET", "/api/me/sessions", auth="user")
def my_sessions(ctx: Ctx) -> Response:
    assert ctx.session is not None
    rows = ctx.db.execute("SELECT * FROM sessions WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?"
                          " ORDER BY last_seen_at DESC", (ctx.uid, now())).fetchall()
    return Response.json({"sessions": [{
        "id": r["id"], "client": r["client"], "auth_method": r["auth_method"], "scope": r["scope"],
        "created_at": iso(r["created_at"]), "last_seen_at": iso(r["last_seen_at"]),
        "current": r["id"] == ctx.session["id"]} for r in rows]})


@router.route("DELETE", "/api/me/sessions/{id:int}", auth="user")
def delete_my_session(ctx: Ctx) -> Response:
    cur = ctx.db.execute("UPDATE sessions SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at IS NULL",
                         (now(), ctx.req.params["id"], ctx.uid))
    if cur.rowcount == 0:
        raise ApiError(404, "not_found", "見つかりません")
    return Response.empty()


# ------------------------------------------------------------------ パスキー（共通）

def _new_challenge(db: sqlite3.Connection, kind: str, company_id: Optional[int], user_id: Optional[int]) -> Dict[str, Any]:
    challenge = secrets.token_bytes(32)
    challenge_id = secrets.token_urlsafe(24)
    db.execute("DELETE FROM webauthn_challenges WHERE expires_at < ?", (now() - 3600,))
    db.execute("INSERT INTO webauthn_challenges (id, kind, company_id, user_id, challenge, expires_at)"
               " VALUES (?, ?, ?, ?, ?, ?)",
               (challenge_id, kind, company_id, user_id, webauthn.b64u_encode(challenge), now() + CHALLENGE_TTL))
    return {"id": challenge_id, "challenge": webauthn.b64u_encode(challenge)}


def _take_challenge(db: sqlite3.Connection, challenge_id: Any, kind: str) -> sqlite3.Row:
    if not isinstance(challenge_id, str):
        raise ApiError(400, "invalid_challenge", "パスキーの手続きをやり直してください")
    row = db.execute("SELECT * FROM webauthn_challenges WHERE id = ? AND kind = ?", (challenge_id, kind)).fetchone()
    if row is None or row["used_at"] is not None or row["expires_at"] < now():
        raise ApiError(400, "invalid_challenge", "パスキーの手続きの有効期限が切れました。もう一度やり直してください")
    db.execute("UPDATE webauthn_challenges SET used_at = ? WHERE id = ?", (now(), challenge_id))
    db.commit()  # 後の処理が失敗しても、チャレンジは使用済みのままにする（再利用させない）
    return row


def _passkey_json(r: sqlite3.Row) -> Dict[str, Any]:
    return {"id": r["id"], "name": r["name"], "created_at": iso(r["created_at"]),
            "last_used_at": iso(r["last_used_at"]), "backed_up": bool(r["backed_up"])}


def _valid_app_redirect(cfg: Any, uri: Any) -> bool:
    if not isinstance(uri, str) or len(uri) > 300:
        return False
    p = urlparse(uri)
    if p.scheme == cfg.app_scheme and p.netloc in ("auth", "passkey") and not p.query:
        return True
    # デスクトップ（Windows など）はループバックで受け取る
    try:
        port = p.port
    except ValueError:
        return False
    return p.scheme == "http" and p.hostname in ("localhost", "127.0.0.1") and port is not None and not p.query


# ------------------------------------------------------------------ パスキーの登録

@router.route("GET", "/api/me/passkeys", auth="user")
def list_passkeys(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM passkeys WHERE user_id = ? ORDER BY id", (ctx.uid,)).fetchall()
    return Response.json({"passkeys": [_passkey_json(r) for r in rows]})


@router.route("DELETE", "/api/me/passkeys/{id:int}", auth="user")
def delete_passkey(ctx: Ctx) -> Response:
    cur = ctx.db.execute("DELETE FROM passkeys WHERE id = ? AND user_id = ?", (ctx.req.params["id"], ctx.uid))
    if cur.rowcount == 0:
        raise ApiError(404, "not_found", "見つかりません")
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="auth.passkey.deleted",
          target_type="passkey", target_id=ctx.req.params["id"], ip=ctx.req.ip)
    return Response.empty()


@router.route("POST", "/api/me/passkeys/ticket", auth="user")
def passkey_ticket(ctx: Ctx) -> Response:
    ticket = secrets.token_urlsafe(32)
    expires = now() + TICKET_TTL
    ctx.db.execute("INSERT INTO passkey_tickets (ticket_hash, user_id, expires_at) VALUES (?, ?, ?)",
                   (hash_token(ticket), ctx.uid, expires))
    return Response.json({"ticket": ticket, "expires_at": iso(expires),
                          "register_url": ctx.cfg.public_url + "/passkey/register?" + urlencode({"ticket": ticket})})


@router.route("POST", "/api/passkeys/register/options", auth="public")
def register_options(ctx: Ctx) -> Response:
    ctx.app.rate.check("pkreg:" + ctx.req.ip, limit=30, window=300)
    ticket = ctx.req.json().get("ticket")
    if isinstance(ticket, str) and ticket:
        row = ctx.db.execute("SELECT * FROM passkey_tickets WHERE ticket_hash = ?", (hash_token(ticket),)).fetchone()
        if row is None or row["used_at"] is not None or row["expires_at"] < now():
            raise ApiError(400, "invalid_ticket", "登録用リンクの有効期限が切れました。アプリからもう一度やり直してください")
        ctx.db.execute("UPDATE passkey_tickets SET used_at = ? WHERE ticket_hash = ?", (now(), hash_token(ticket)))
        user_id = row["user_id"]
    else:
        ctx.app.authenticate(ctx, "user")  # ブラウザ（管理コンソール）から Bearer で呼ぶ場合
        user_id = ctx.uid
    user = ctx.db.execute("SELECT u.*, c.code AS company_code, c.name AS company_name FROM users u"
                          " JOIN companies c ON c.id = u.company_id WHERE u.id = ?", (user_id,)).fetchone()
    if user is None or user["status"] != "active" or user["must_change_password"]:
        raise ApiError(403, "forbidden", "この操作はできません")
    existing = ctx.db.execute("SELECT credential_id, transports FROM passkeys WHERE user_id = ?", (user_id,)).fetchall()
    ch = _new_challenge(ctx.db, "register", user["company_id"], user_id)
    return Response.json({"challenge_id": ch["id"], "publicKey": {
        "challenge": ch["challenge"],
        "rp": {"id": ctx.cfg.rp_id, "name": ctx.cfg.rp_name},
        "user": {"id": user["user_handle"],
                 "name": "%s/%s" % (user["company_code"], user["employee_code"]),
                 "displayName": "%s（%s）" % (user["display_name"], user["company_name"])},
        "pubKeyCredParams": [{"type": "public-key", "alg": webauthn.ALG_ES256},
                             {"type": "public-key", "alg": webauthn.ALG_RS256}],
        "timeout": CHALLENGE_TTL * 1000,
        "attestation": "none",
        "authenticatorSelection": {"residentKey": "required", "requireResidentKey": True,
                                   "userVerification": "required"},
        "excludeCredentials": [{"type": "public-key", "id": r["credential_id"]} for r in existing],
    }})


@router.route("POST", "/api/passkeys/register/verify", auth="public")
def register_verify(ctx: Ctx) -> Response:
    data = ctx.req.json()
    ch = _take_challenge(ctx.db, data.get("challenge_id"), "register")
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (ch["user_id"],)).fetchone()
    if user is None or user["status"] != "active":
        raise ApiError(403, "forbidden", "この操作はできません")
    try:
        result = webauthn.verify_registration(
            data.get("credential"), challenge=webauthn.b64u_decode(ch["challenge"]),
            origins=ctx.cfg.allowed_origins, rp_id=ctx.cfg.rp_id)
    except webauthn.WebAuthnError as exc:
        ctx.app.log("passkey registration rejected: %s" % exc)
        raise ApiError(400, "passkey_invalid", "パスキーを確認できませんでした。もう一度お試しください")
    if ctx.db.execute("SELECT 1 FROM passkeys WHERE credential_id = ?", (result["credential_id"],)).fetchone():
        raise ApiError(409, "passkey_exists", "このパスキーは既に登録されています")
    name = data.get("name") if isinstance(data.get("name"), str) else ""
    name = name.strip()[:40] or "パスキー"
    cur = ctx.db.execute(
        "INSERT INTO passkeys (user_id, credential_id, public_key, alg, sign_count, transports, aaguid, backed_up,"
        " name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (user["id"], result["credential_id"], result["public_key"], result["alg"], result["sign_count"],
         ",".join(result["transports"]), result["aaguid"], int(result["backed_up"]), name, now()))
    audit(ctx.db, company_id=user["company_id"], actor_id=user["id"], action="auth.passkey.registered",
          target_type="passkey", target_id=cur.lastrowid, detail={"name": name}, ip=ctx.req.ip)
    row = ctx.db.execute("SELECT * FROM passkeys WHERE id = ?", (cur.lastrowid,)).fetchone()
    return Response.json({"passkey": _passkey_json(row)})


# ------------------------------------------------------------------ パスキーでログイン

@router.route("POST", "/api/auth/passkey/options", auth="public")
def passkey_options(ctx: Ctx) -> Response:
    ctx.app.rate.check("pklogin:" + ctx.req.ip, limit=30, window=300)
    company_code = ctx.req.str_field("company_code", label="企業コード", max_len=32)
    login_id = ctx.req.str_field("login_id", required=False, max_len=254)
    company = _company_by_code(ctx.db, company_code)
    # login_id は受け付けるが allowCredentials には使わない（登録済みかどうかを推測させないため）。
    # パスキーは端末に保存される方式（residentKey=required）なので、端末側の一覧から選べる。
    # 企業コードや利用者が存在しなくても同じ形で返す（存在の有無を推測させない）
    ch = _new_challenge(ctx.db, "login", company["id"] if company else None, None)
    return Response.json({"challenge_id": ch["id"], "publicKey": {
        "challenge": ch["challenge"], "rpId": ctx.cfg.rp_id, "timeout": CHALLENGE_TTL * 1000,
        "userVerification": "required", "allowCredentials": []}})


@router.route("POST", "/api/auth/passkey/verify", auth="public")
def passkey_verify(ctx: Ctx) -> Response:
    req = ctx.req
    data = req.json()
    ch = _take_challenge(ctx.db, data.get("challenge_id"), "login")
    redirect = data.get("app_redirect")
    if redirect is not None:
        if not isinstance(redirect, dict):
            raise ApiError(400, "invalid_redirect", "アプリへの戻り先が正しくありません")
        uri = redirect.get("redirect_uri")
        challenge = redirect.get("code_challenge")
        state = redirect.get("state") if isinstance(redirect.get("state"), str) else ""
        if not _valid_app_redirect(ctx.cfg, uri) or not isinstance(challenge, str) or not 43 <= len(challenge) <= 128:
            raise ApiError(400, "invalid_redirect", "アプリへの戻り先が正しくありません")
    credential = data.get("credential")
    fail = ApiError(401, "passkey_failed", "パスキーでログインできませんでした。企業コードを確認するか、パスワードでログインしてください")
    if ch["company_id"] is None or not isinstance(credential, dict):
        raise fail
    cred_id = credential.get("id") if isinstance(credential.get("id"), str) else ""
    row = ctx.db.execute(
        "SELECT p.*, u.company_id, u.user_handle FROM passkeys p JOIN users u ON u.id = p.user_id"
        " WHERE p.credential_id = ? AND u.company_id = ?", (cred_id, ch["company_id"])).fetchone()
    if row is None:
        raise fail
    handle = (credential.get("response") or {}).get("userHandle")
    if handle and handle != row["user_handle"]:
        raise fail
    try:
        new_count = webauthn.verify_authentication(
            credential, challenge=webauthn.b64u_decode(ch["challenge"]), origins=ctx.cfg.allowed_origins,
            rp_id=ctx.cfg.rp_id, public_key=bytes(row["public_key"]), stored_sign_count=row["sign_count"])
    except webauthn.WebAuthnError as exc:
        ctx.app.log("passkey login rejected: %s" % exc)
        audit(ctx.db, company_id=row["company_id"], actor_id=row["user_id"], action="auth.login.failure",
              detail={"method": "passkey"}, ip=req.ip)
        ctx.db.commit()
        raise fail
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (row["user_id"],)).fetchone()
    company = ctx.db.execute("SELECT * FROM companies WHERE id = ?", (user["company_id"],)).fetchone()
    _check_login_allowed(ctx, user, company)
    ctx.db.execute("UPDATE passkeys SET sign_count = ?, last_used_at = ? WHERE id = ?", (new_count, now(), row["id"]))
    _record_success(ctx, user, company, "passkey")

    if isinstance(redirect, dict):
        code = secrets.token_urlsafe(32)
        ctx.db.execute("INSERT INTO app_auth_codes (code_hash, user_id, code_challenge, redirect_uri, expires_at)"
                       " VALUES (?, ?, ?, ?, ?)", (hash_token(code), user["id"], challenge, uri, now() + APP_CODE_TTL))
        return Response.json({"status": "redirect",
                              "redirect_url": uri + "?" + urlencode({"code": code, "state": state[:200]})})

    client = device_label({"platform": "web"}, req.headers.get("user-agent", ""))
    token = create_session(ctx.db, user, company, scope="full", method="passkey", client=client, ip=req.ip)
    return Response.json(login_payload(ctx.db, user["id"], company, token, "ok"))


@router.route("POST", "/api/auth/exchange", auth="public")
def exchange(ctx: Ctx) -> Response:
    req = ctx.req
    ctx.app.rate.check("exchange:" + req.ip, limit=30, window=300)
    code = req.json().get("code")
    verifier = req.json().get("code_verifier")
    invalid = ApiError(400, "invalid_code", "ログインの手続きの有効期限が切れました。もう一度やり直してください")
    if not isinstance(code, str) or not isinstance(verifier, str) or not 43 <= len(verifier) <= 128:
        raise invalid
    row = ctx.db.execute("SELECT * FROM app_auth_codes WHERE code_hash = ?", (hash_token(code),)).fetchone()
    if row is None or row["used_at"] is not None or row["expires_at"] < now():
        raise invalid
    ctx.db.execute("UPDATE app_auth_codes SET used_at = ? WHERE code_hash = ?", (now(), row["code_hash"]))
    expected = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii", "replace")).digest()).rstrip(b"=")
    if not hmac.compare_digest(expected.decode("ascii"), row["code_challenge"]):
        ctx.db.commit()
        raise invalid
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (row["user_id"],)).fetchone()
    company = ctx.db.execute("SELECT * FROM companies WHERE id = ?", (user["company_id"],)).fetchone()
    _check_login_allowed(ctx, user, company)
    client = device_label(req.json().get("device"), req.headers.get("user-agent", ""))
    token = create_session(ctx.db, user, company, scope="full", method="passkey", client=client, ip=req.ip)
    return Response.json(login_payload(ctx.db, user["id"], company, token, "ok"))
