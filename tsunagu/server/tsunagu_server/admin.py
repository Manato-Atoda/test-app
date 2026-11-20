"""企業管理者向け API（社員アカウントの発行・管理、チャンネル、通報、監査ログ、設定）。

すべて role=admin かつ自分の企業（company_id）の範囲だけを扱う。
"""
from __future__ import annotations

import csv
import io
import json
import re
import sqlite3
from datetime import datetime, timedelta
from typing import Any, Dict, List

from . import passwords
from .accounts import (account_state, insert_user, issuable, issue_credentials, revoke_sessions,
                       send_credentials_mail, user_summary, users_by_ids, validate_user_fields)
from .db import DEFAULT_SETTINGS, JST, audit, company_settings, iso, jp_datetime, now
from .pdf import build_account_notices_pdf
from .web import ApiError, Ctx, Response, Router

router = Router()
CSV_COLUMNS = ["employee_code", "email", "display_name", "department", "title", "role"]
CSV_LABELS = {"employee_code": "社員コード", "email": "メールアドレス", "display_name": "氏名",
              "department": "部署", "title": "役職", "role": "権限"}


def _admin_user_json(db: sqlite3.Connection, u: sqlite3.Row) -> Dict[str, Any]:
    data = user_summary(u)
    data.update({
        "email": u["email"],
        "account_state": account_state(u),
        "credentials_issued_at": iso(u["credentials_issued_at"]),
        "credentials_issued_via": u["credentials_issued_via"],
        "temp_password_expires_at": iso(u["temp_password_expires_at"]) if u["must_change_password"] else None,
        "last_login_at": iso(u["last_login_at"]),
        "locked_until": iso(u["locked_until"]) if u["locked_until"] and u["locked_until"] > now() else None,
        "passkey_count": db.execute("SELECT COUNT(*) FROM passkeys WHERE user_id = ?", (u["id"],)).fetchone()[0],
        "created_at": iso(u["created_at"]),
    })
    return data


def _user(ctx: Ctx) -> sqlite3.Row:
    row = ctx.db.execute("SELECT * FROM users WHERE id = ? AND company_id = ?",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "社員が見つかりません")
    return row


def _other_admins(ctx: Ctx, user_id: int) -> int:
    return ctx.db.execute("SELECT COUNT(*) FROM users WHERE company_id = ? AND role = 'admin' AND status = 'active'"
                          " AND id != ?", (ctx.cid, user_id)).fetchone()[0]


def _csv_response(rows: List[List[Any]], filename: str) -> Response:
    buf = io.StringIO()
    csv.writer(buf, lineterminator="\r\n").writerows(rows)
    # Excel で文字化けしないよう BOM 付き UTF-8
    return Response.download(("﻿" + buf.getvalue()).encode("utf-8"), "text/csv; charset=utf-8", filename)


# ------------------------------------------------------------------ 概要

@router.route("GET", "/api/admin/stats", auth="admin")
def stats(ctx: Ctx) -> Response:
    users = ctx.db.execute("SELECT * FROM users WHERE company_id = ?", (ctx.cid,)).fetchall()
    states: Dict[str, int] = {}
    for u in users:
        s = account_state(u)
        states[s] = states.get(s, 0) + 1
    week = now() - 7 * 86400
    return Response.json({
        "users_total": len([u for u in users if u["status"] != "retired"]),
        "account_states": states,
        "posts_7d": ctx.db.execute("SELECT COUNT(*) FROM posts WHERE company_id = ? AND created_at >= ?"
                                   " AND deleted_at IS NULL", (ctx.cid, week)).fetchone()[0],
        "active_users_7d": ctx.db.execute("SELECT COUNT(*) FROM users WHERE company_id = ? AND last_login_at >= ?",
                                          (ctx.cid, week)).fetchone()[0],
        "open_reports": ctx.db.execute("SELECT COUNT(*) FROM reports WHERE company_id = ? AND status = 'open'",
                                       (ctx.cid,)).fetchone()[0],
        "mail_mode": ctx.cfg.mail_mode,
    })


# ------------------------------------------------------------------ 社員

@router.route("GET", "/api/admin/users", auth="admin")
def list_users(ctx: Ctx) -> Response:
    q = (ctx.req.query.get("q") or "").strip().lower()
    state = ctx.req.query.get("state") or ""
    rows = ctx.db.execute("SELECT * FROM users WHERE company_id = ? ORDER BY employee_code", (ctx.cid,)).fetchall()
    out = []
    for u in rows:
        if q and not any(q in (u[k] or "").lower() for k in ("employee_code", "display_name", "email",
                                                             "department", "title")):
            continue
        if state and account_state(u) != state:
            continue
        out.append(_admin_user_json(ctx.db, u))
    return Response.json({"users": out})


@router.route("POST", "/api/admin/users", auth="admin")
def create_user(ctx: Ctx) -> Response:
    fields = validate_user_fields(ctx.req.json())
    user_id = insert_user(ctx.db, ctx.cid, fields, ctx.uid)
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.user.created", target_type="user",
          target_id=user_id, detail={"employee_code": fields["employee_code"], "role": fields["role"]}, ip=ctx.req.ip)
    user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return Response.json({"user": _admin_user_json(ctx.db, user)})


@router.route("PATCH", "/api/admin/users/{id:int}", auth="admin")
def update_user(ctx: Ctx) -> Response:
    user = _user(ctx)
    fields = validate_user_fields(ctx.req.json(), partial=True)
    fields.pop("employee_code", None)  # 社員コードはログイン ID なので変更しない
    if fields.get("role") == "member" and user["role"] == "admin" and _other_admins(ctx, user["id"]) == 0:
        raise ApiError(400, "last_admin", "最後の管理者の権限は外せません")
    if fields.get("email") and fields["email"] != user["email"]:
        dup = ctx.db.execute("SELECT 1 FROM users WHERE company_id = ? AND email = ? AND id != ?",
                             (ctx.cid, fields["email"], user["id"])).fetchone()
        if dup:
            raise ApiError(409, "duplicate_email", "このメールアドレスは既に登録されています", field="email")
    changes = {k: v for k, v in fields.items() if user[k] != v}
    if changes:
        sets = ", ".join("%s = ?" % k for k in changes)
        ctx.db.execute("UPDATE users SET %s, updated_at = ? WHERE id = ?" % sets,
                       list(changes.values()) + [now(), user["id"]])
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.user.updated", target_type="user",
              target_id=user["id"], detail={"changed": sorted(changes)}, ip=ctx.req.ip)
    return Response.json({"user": _admin_user_json(ctx.db, _user(ctx))})


@router.route("POST", "/api/admin/users/{id:int}/status", auth="admin")
def set_status(ctx: Ctx) -> Response:
    user = _user(ctx)
    status = ctx.req.json().get("status")
    if status not in ("active", "suspended", "retired"):
        raise ApiError(400, "invalid_field", "状態が正しくありません")
    if user["id"] == ctx.uid and status != "active":
        raise ApiError(400, "self", "自分自身を停止することはできません")
    if user["role"] == "admin" and status != "active" and _other_admins(ctx, user["id"]) == 0:
        raise ApiError(400, "last_admin", "最後の管理者は停止できません")
    if status != user["status"]:
        ctx.db.execute("UPDATE users SET status = ?, updated_at = ? WHERE id = ?", (status, now(), user["id"]))
        revoked = revoke_sessions(ctx.db, user["id"]) if status != "active" else 0
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.user.status_changed", target_type="user",
              target_id=user["id"], detail={"from": user["status"], "to": status, "sessions_revoked": revoked},
              ip=ctx.req.ip)
    return Response.json({"user": _admin_user_json(ctx.db, _user(ctx))})


@router.route("POST", "/api/admin/users/{id:int}/unlock", auth="admin")
def unlock(ctx: Ctx) -> Response:
    user = _user(ctx)
    ctx.db.execute("UPDATE users SET locked_until = NULL, failed_attempts = 0 WHERE id = ?", (user["id"],))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.user.unlocked", target_type="user",
          target_id=user["id"], ip=ctx.req.ip)
    return Response.json({"user": _admin_user_json(ctx.db, _user(ctx))})


@router.route("POST", "/api/admin/users/{id:int}/revoke-sessions", auth="admin")
def revoke(ctx: Ctx) -> Response:
    user = _user(ctx)
    count = revoke_sessions(ctx.db, user["id"], ctx.session["id"] if user["id"] == ctx.uid and ctx.session else None)
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.sessions.revoked", target_type="user",
          target_id=user["id"], detail={"count": count}, ip=ctx.req.ip)
    return Response.json({"revoked": count})


@router.route("POST", "/api/admin/users/{id:int}/delete-passkeys", auth="admin")
def delete_passkeys(ctx: Ctx) -> Response:
    user = _user(ctx)
    count = ctx.db.execute("DELETE FROM passkeys WHERE user_id = ?", (user["id"],)).rowcount
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.passkeys.deleted", target_type="user",
          target_id=user["id"], detail={"count": count}, ip=ctx.req.ip)
    return Response.json({"deleted": count})


@router.route("POST", "/api/admin/credentials", auth="admin")
def issue(ctx: Ctx) -> Response:
    """アカウント情報（仮パスワード）を発行して、PDF で返すかメールで送る。"""
    data = ctx.req.json()
    method = data.get("method")
    ids = data.get("user_ids")
    if method not in ("email", "pdf"):
        raise ApiError(400, "invalid_field", "発行方法を選んでください（メール / PDF）")
    if not isinstance(ids, list) or not ids or not all(isinstance(i, int) for i in ids) or len(ids) > 500:
        raise ApiError(400, "invalid_field", "発行する社員を選んでください（一度に500人まで）")
    users = users_by_ids(ctx.db, ctx.cid, ids)
    if len(users) != len(set(ids)):
        raise ApiError(404, "not_found", "選択した社員の一部が見つかりません")
    ctx.app.rate.check("issue:%d" % ctx.uid, limit=60, window=600)

    skipped, notices, sent = [], [], []
    for u in users:
        ok, reason = issuable(u)
        if ok and method == "email" and not u["email"]:
            ok, reason = False, "メールアドレスが登録されていません"
        if not ok:
            skipped.append({"id": u["id"], "employee_code": u["employee_code"], "reason": reason})
            continue
        notice = issue_credentials(ctx.db, ctx.cfg, ctx.company, u, method=method, actor_id=ctx.uid, ip=ctx.req.ip)
        if method == "email":
            if send_credentials_mail(ctx.db, ctx.cfg, ctx.cid, notice):
                sent.append(u["id"])
            else:
                skipped.append({"id": u["id"], "employee_code": u["employee_code"], "reason": "メールの送信に失敗しました"})
        else:
            notices.append(notice)

    if method == "pdf":
        if not notices:
            raise ApiError(400, "nothing_issued", "発行できる社員がいません", skipped=skipped)
        pdf = build_account_notices_pdf(notices)
        name = "account-notice-%s.pdf" % jp_datetime(now(), False)[:11].replace("年", "").replace("月", "").replace("日", "")
        resp = Response.download(pdf, "application/pdf", name)
        resp.headers["X-Tsunagu-Issued"] = str(len(notices))
        resp.headers["X-Tsunagu-Skipped"] = str(len(skipped))
        return resp
    return Response.json({"sent": sent, "skipped": skipped, "mail_mode": ctx.cfg.mail_mode})


@router.route("POST", "/api/admin/users/import", auth="admin")
def import_users(ctx: Ctx) -> Response:
    text = ctx.req.json().get("csv")
    if not isinstance(text, str) or not text.strip():
        raise ApiError(400, "required", "CSV を貼り付けるか、ファイルを選んでください")
    text = text.lstrip("﻿")
    rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        raise ApiError(400, "required", "CSV が空です")
    header = [h.strip().lower() for h in rows[0]]
    reverse_labels = {v: k for k, v in CSV_LABELS.items()}
    header = [reverse_labels.get(h, h) for h in header]
    if "employee_code" not in header or "display_name" not in header:
        raise ApiError(400, "invalid_csv", "1行目に見出し（employee_code, display_name など）が必要です")
    if len(rows) > 2001:
        raise ApiError(400, "too_many", "一度に取り込めるのは2000人までです")
    created, errors = [], []
    for line_no, row in enumerate(rows[1:], start=2):
        if not any(cell.strip() for cell in row):
            continue
        record = {header[i]: cell for i, cell in enumerate(row) if i < len(header)}
        try:
            ctx.db.execute("SAVEPOINT import_row")
            fields = validate_user_fields(record)
            uid = insert_user(ctx.db, ctx.cid, fields, ctx.uid)
            ctx.db.execute("RELEASE import_row")
            created.append(uid)
        except ApiError as err:
            ctx.db.execute("ROLLBACK TO import_row")
            ctx.db.execute("RELEASE import_row")
            errors.append({"line": line_no, "message": err.message})
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.users.imported",
          detail={"created": len(created), "errors": len(errors)}, ip=ctx.req.ip)
    return Response.json({"created": len(created), "created_ids": created, "errors": errors})


@router.route("GET", "/api/admin/users/export", auth="admin")
def export_users(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM users WHERE company_id = ? ORDER BY employee_code", (ctx.cid,)).fetchall()
    out = [CSV_COLUMNS + ["status", "account_state", "last_login_at"]]
    for u in rows:
        out.append([u["employee_code"], u["email"] or "", u["display_name"], u["department"], u["title"], u["role"],
                     u["status"], account_state(u), iso(u["last_login_at"]) or ""])
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.users.exported", ip=ctx.req.ip)
    return _csv_response(out, "users-%s.csv" % ctx.company["code"])


# ------------------------------------------------------------------ チャンネル

def _admin_channel_json(ctx: Ctx, c: sqlite3.Row) -> Dict[str, Any]:
    if c["company_wide"]:
        members = ctx.db.execute("SELECT COUNT(*) FROM users WHERE company_id = ? AND status = 'active'",
                                 (ctx.cid,)).fetchone()[0]
    else:
        members = ctx.db.execute("SELECT COUNT(*) FROM channel_members WHERE channel_id = ?", (c["id"],)).fetchone()[0]
    return {"id": c["id"], "name": c["name"], "emoji": c["emoji"], "description": c["description"],
            "visibility": c["visibility"],
            "company_wide": bool(c["company_wide"]), "post_policy": c["post_policy"], "archived": bool(c["archived"]),
            "member_count": members, "created_at": iso(c["created_at"])}


def _channel_fields(ctx: Ctx, partial: bool) -> Dict[str, Any]:
    data = ctx.req.json()
    out: Dict[str, Any] = {}
    if not partial or "name" in data:
        out["name"] = ctx.req.str_field("name", label="チャンネル名", max_len=40)
    if not partial or "description" in data:
        out["description"] = ctx.req.str_field("description", required=False, label="説明", max_len=200)
    if not partial or "emoji" in data:
        out["emoji"] = ctx.req.str_field("emoji", required=False, label="絵文字", max_len=8) or None
    if not partial or "visibility" in data:
        out["visibility"] = data.get("visibility") or "open"
        if out["visibility"] not in ("open", "private"):
            raise ApiError(400, "invalid_field", "公開範囲が正しくありません")
    if not partial or "post_policy" in data:
        out["post_policy"] = data.get("post_policy") or "everyone"
        if out["post_policy"] not in ("everyone", "admins"):
            raise ApiError(400, "invalid_field", "投稿できる人の設定が正しくありません")
    if not partial or "company_wide" in data:
        out["company_wide"] = int(bool(data.get("company_wide")))
    if partial and "archived" in data:
        out["archived"] = int(bool(data.get("archived")))
    if out.get("company_wide"):
        out["visibility"] = "open"
    return out


def _channel(ctx: Ctx) -> sqlite3.Row:
    row = ctx.db.execute("SELECT * FROM channels WHERE id = ? AND company_id = ? AND system_kind IS NULL",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "チャンネルが見つかりません")
    return row


@router.route("GET", "/api/admin/channels", auth="admin")
def admin_channels(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM channels WHERE company_id = ? AND system_kind IS NULL"
                          " ORDER BY archived, company_wide DESC, sort_order, name", (ctx.cid,)).fetchall()
    return Response.json({"channels": [_admin_channel_json(ctx, c) for c in rows]})


@router.route("POST", "/api/admin/channels", auth="admin")
def create_channel(ctx: Ctx) -> Response:
    fields = _channel_fields(ctx, partial=False)
    if ctx.db.execute("SELECT 1 FROM channels WHERE company_id = ? AND name = ?", (ctx.cid, fields["name"])).fetchone():
        raise ApiError(409, "duplicate", "同じ名前のチャンネルがあります", field="name")
    cur = ctx.db.execute(
        "INSERT INTO channels (company_id, name, emoji, description, visibility, company_wide, post_policy,"
        " created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (ctx.cid, fields["name"], fields["emoji"], fields["description"], fields["visibility"],
         fields["company_wide"], fields["post_policy"], ctx.uid, now()))
    if not fields["company_wide"]:
        ctx.db.execute("INSERT OR IGNORE INTO channel_members (channel_id, user_id, joined_at) VALUES (?, ?, ?)",
                       (cur.lastrowid, ctx.uid, now()))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.channel.created", target_type="channel",
          target_id=cur.lastrowid, detail=fields, ip=ctx.req.ip)
    row = ctx.db.execute("SELECT * FROM channels WHERE id = ?", (cur.lastrowid,)).fetchone()
    return Response.json({"channel": _admin_channel_json(ctx, row)})


@router.route("PATCH", "/api/admin/channels/{id:int}", auth="admin")
def update_channel(ctx: Ctx) -> Response:
    channel = _channel(ctx)
    fields = _channel_fields(ctx, partial=True)
    if "name" in fields and fields["name"] != channel["name"] and ctx.db.execute(
            "SELECT 1 FROM channels WHERE company_id = ? AND name = ?", (ctx.cid, fields["name"])).fetchone():
        raise ApiError(409, "duplicate", "同じ名前のチャンネルがあります", field="name")
    if fields:
        sets = ", ".join("%s = ?" % k for k in fields)
        ctx.db.execute("UPDATE channels SET %s WHERE id = ?" % sets, list(fields.values()) + [channel["id"]])
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.channel.updated", target_type="channel",
              target_id=channel["id"], detail=fields, ip=ctx.req.ip)
    return Response.json({"channel": _admin_channel_json(ctx, _channel(ctx))})


@router.route("GET", "/api/admin/channels/{id:int}/members", auth="admin")
def channel_members(ctx: Ctx) -> Response:
    channel = _channel(ctx)
    rows = ctx.db.execute("SELECT u.* FROM channel_members cm JOIN users u ON u.id = cm.user_id"
                          " WHERE cm.channel_id = ? ORDER BY u.department, u.employee_code", (channel["id"],)).fetchall()
    return Response.json({"members": [user_summary(u) for u in rows]})


@router.route("POST", "/api/admin/channels/{id:int}/members", auth="admin")
def add_channel_members(ctx: Ctx) -> Response:
    channel = _channel(ctx)
    if channel["company_wide"]:
        raise ApiError(400, "not_allowed", "全社チャンネルは全員が自動で参加しています")
    codes = ctx.req.json().get("employee_codes")
    if not isinstance(codes, list) or not codes or len(codes) > 500:
        raise ApiError(400, "required", "社員コードを入力してください")
    added, missing = 0, []
    for code in codes:
        if not isinstance(code, str) or not code.strip():
            continue
        user = ctx.db.execute("SELECT id FROM users WHERE company_id = ? AND employee_code = ?",
                              (ctx.cid, code.strip())).fetchone()
        if user is None:
            missing.append(code.strip())
            continue
        added += ctx.db.execute("INSERT OR IGNORE INTO channel_members (channel_id, user_id, joined_at)"
                                " VALUES (?, ?, ?)", (channel["id"], user["id"], now())).rowcount
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.channel.members_added", target_type="channel",
          target_id=channel["id"], detail={"added": added}, ip=ctx.req.ip)
    return Response.json({"added": added, "not_found": missing})


@router.route("DELETE", "/api/admin/channels/{id:int}/members/{user_id:int}", auth="admin")
def remove_channel_member(ctx: Ctx) -> Response:
    channel = _channel(ctx)
    ctx.db.execute("DELETE FROM channel_members WHERE channel_id = ? AND user_id = ?",
                   (channel["id"], ctx.req.params["user_id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.channel.member_removed", target_type="channel",
          target_id=channel["id"], detail={"user_id": ctx.req.params["user_id"]}, ip=ctx.req.ip)
    return Response.empty()


# ------------------------------------------------------------------ 通報

@router.route("GET", "/api/admin/reports", auth="admin")
def list_reports(ctx: Ctx) -> Response:
    status = ctx.req.query.get("status") or "open"
    rows = ctx.db.execute("SELECT * FROM reports WHERE company_id = ? AND status = ? ORDER BY id DESC LIMIT 200",
                          (ctx.cid, status)).fetchall()
    out = []
    for r in rows:
        table = "posts" if r["target_type"] == "post" else "comments"
        target = ctx.db.execute("SELECT * FROM %s WHERE id = ? AND company_id = ?" % table,
                                (r["target_id"], ctx.cid)).fetchone()
        reporter = ctx.db.execute("SELECT * FROM users WHERE id = ?", (r["reporter_id"],)).fetchone()
        author = ctx.db.execute("SELECT * FROM users WHERE id = ?", (target["author_id"],)).fetchone() if target else None
        out.append({
            "id": r["id"], "target_type": r["target_type"], "target_id": r["target_id"], "reason": r["reason"],
            "status": r["status"], "resolution": r["resolution"], "created_at": iso(r["created_at"]),
            "reporter": user_summary(reporter), "author": user_summary(author) if author else None,
            "author_identity": (target["identity"] if target else "real"),
            "author_display_name": (target["display_name"] if target else None),
            "body": target["body"] if target else "",
            "target_removed": bool(target is None or target["deleted_at"] or target["hidden_at"]),
        })
    return Response.json({"reports": out})


@router.route("POST", "/api/admin/reports/{id:int}/resolve", auth="admin")
def resolve_report(ctx: Ctx) -> Response:
    report = ctx.db.execute("SELECT * FROM reports WHERE id = ? AND company_id = ?",
                            (ctx.req.params["id"], ctx.cid)).fetchone()
    if report is None:
        raise ApiError(404, "not_found", "通報が見つかりません")
    action = ctx.req.json().get("action")
    if action not in ("hide", "dismiss"):
        raise ApiError(400, "invalid_field", "対応を選んでください")
    ts = now()
    if action == "hide":
        table = "posts" if report["target_type"] == "post" else "comments"
        extra = ", hidden_reason = ?" if table == "posts" else ""
        params: List[Any] = [ts, ctx.uid] + (["通報により非表示"] if table == "posts" else []) + [report["target_id"], ctx.cid]
        ctx.db.execute("UPDATE %s SET hidden_at = ?, hidden_by = ?%s WHERE id = ? AND company_id = ?" % (table, extra),
                       params)
    # 同じ対象への未対応の通報はまとめて対応済みにする
    ctx.db.execute("UPDATE reports SET status = 'resolved', resolution = ?, resolved_by = ?, resolved_at = ?"
                   " WHERE company_id = ? AND target_type = ? AND target_id = ? AND status = 'open'",
                   (action, ctx.uid, ts, ctx.cid, report["target_type"], report["target_id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.report.resolved",
          target_type=report["target_type"], target_id=report["target_id"], detail={"action": action}, ip=ctx.req.ip)
    return Response.json({"ok": True})


# ------------------------------------------------------------------ 監査ログ

AUDIT_LABELS = {
    "auth.login.success": "ログイン", "auth.login.failure": "ログイン失敗", "auth.login.blocked": "ログイン拒否",
    "auth.password.changed": "パスワード変更", "auth.password.change_failed": "パスワード変更失敗",
    "auth.passkey.registered": "パスキー登録", "auth.passkey.deleted": "パスキー削除",
    "auth.logout_all": "全端末ログアウト", "user.guidelines.accepted": "ガイドライン同意",
    "admin.user.created": "社員登録", "admin.user.updated": "社員情報変更", "admin.user.status_changed": "利用状態変更",
    "admin.credentials.issued": "アカウント情報発行", "admin.user.unlocked": "ロック解除",
    "admin.sessions.revoked": "強制ログアウト", "admin.passkeys.deleted": "パスキー削除（管理者）",
    "admin.users.imported": "CSV一括登録", "admin.users.exported": "社員CSV出力",
    "admin.channel.created": "チャンネル作成", "admin.channel.updated": "チャンネル変更",
    "admin.channel.members_added": "メンバー追加", "admin.channel.member_removed": "メンバー削除",
    "admin.report.resolved": "通報対応", "admin.settings.updated": "設定変更",
    "admin.audit.exported": "監査ログ出力", "post.deleted": "投稿削除", "comment.deleted": "コメント削除",
    "report.created": "通報", "company.created": "企業作成",
    "question.deleted": "質問削除", "answer.deleted": "回答削除",
    "admin.forest_category.created": "森のカテゴリ作成", "admin.forest_category.updated": "森のカテゴリ変更",
    "admin.insights.generated": "AI レポート作成",
}


def _audit_rows(ctx: Ctx, before: Any, limit: int) -> List[sqlite3.Row]:
    sql = ("SELECT a.*, u.display_name AS actor_name, u.employee_code AS actor_code FROM audit_logs a"
           " LEFT JOIN users u ON u.id = a.actor_id WHERE a.company_id = ?")
    args: List[Any] = [ctx.cid]
    if before:
        sql += " AND a.id < ?"
        args.append(before)
    action = ctx.req.query.get("action")
    if action:
        sql += " AND a.action LIKE ?"
        args.append(action.replace("%", "") + "%")
    return ctx.db.execute(sql + " ORDER BY a.id DESC LIMIT ?", args + [limit]).fetchall()


@router.route("GET", "/api/admin/audit-logs", auth="admin")
def audit_logs(ctx: Ctx) -> Response:
    rows = _audit_rows(ctx, ctx.req.int_query("before"), 101)
    has_more = len(rows) > 100
    rows = rows[:100]
    return Response.json({"logs": [{
        "id": r["id"], "action": r["action"], "label": AUDIT_LABELS.get(r["action"], r["action"]),
        "actor": {"display_name": r["actor_name"], "employee_code": r["actor_code"]} if r["actor_id"] else None,
        "target_type": r["target_type"], "target_id": r["target_id"], "detail": json.loads(r["detail"] or "{}"),
        "ip": r["ip"], "created_at": iso(r["created_at"])} for r in rows],
        "next_before": rows[-1]["id"] if has_more and rows else None})


@router.route("GET", "/api/admin/audit-logs/export", auth="admin")
def export_audit(ctx: Ctx) -> Response:
    rows = _audit_rows(ctx, None, 100000)
    out = [["日時(UTC)", "操作", "操作コード", "実行者の社員コード", "実行者", "対象", "対象ID", "詳細", "IPアドレス"]]
    for r in rows:
        out.append([iso(r["created_at"]), AUDIT_LABELS.get(r["action"], r["action"]), r["action"], r["actor_code"] or "",
                    r["actor_name"] or "", r["target_type"] or "", r["target_id"] or "", r["detail"], r["ip"] or ""])
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.audit.exported", ip=ctx.req.ip)
    return _csv_response(out, "audit-log-%s.csv" % ctx.company["code"])


# ------------------------------------------------------------------ 設定・メール

@router.route("GET", "/api/admin/settings", auth="admin")
def get_settings(ctx: Ctx) -> Response:
    return Response.json({"settings": company_settings(ctx.company), "company": {
        "code": ctx.company["code"], "name": ctx.company["name"]}})


@router.route("PATCH", "/api/admin/settings", auth="admin")
def patch_settings(ctx: Ctx) -> Response:
    data = ctx.req.json()
    current = company_settings(ctx.company)
    ranges = {"password_min_length": (8, 64), "temp_password_ttl_hours": (1, 24 * 14),
              "lockout_threshold": (3, 20), "lockout_minutes": (1, 24 * 60), "session_days": (1, 90)}
    labels = {"password_min_length": "パスワードの最小文字数", "temp_password_ttl_hours": "仮パスワードの有効期限",
              "lockout_threshold": "ロックするまでの失敗回数", "lockout_minutes": "ロック時間",
              "session_days": "ログイン状態の保持日数"}
    changed = []
    for key, (lo, hi) in ranges.items():
        if key in data:
            value = data[key]
            if not isinstance(value, int) or isinstance(value, bool) or not lo <= value <= hi:
                raise ApiError(400, "invalid_field", "%sは%d〜%dの範囲で指定してください" % (labels[key], lo, hi), field=key)
            if current[key] != value:
                current[key] = value
                changed.append(key)
    for flag in ("identity_department_enabled", "identity_anonymous_enabled", "watermark_mobile"):
        if flag in data:
            value = bool(data[flag])
            if current[flag] != value:
                current[flag] = value
                changed.append(flag)
    if "password_require_symbol" in data:
        value = bool(data["password_require_symbol"])
        if current["password_require_symbol"] != value:
            current["password_require_symbol"] = value
            changed.append("password_require_symbol")
    if "guidelines" in data:
        text = data["guidelines"]
        if not isinstance(text, str) or not text.strip() or len(text) > 5000:
            raise ApiError(400, "invalid_field", "ガイドラインは1〜5000文字で入力してください", field="guidelines")
        text = text.replace("\r\n", "\n").strip()
        if text != current["guidelines"]:
            current["guidelines"] = text
            current["guidelines_version"] = int(current["guidelines_version"]) + 1
            changed.append("guidelines")
    if changed:
        stored = {k: v for k, v in current.items() if k in DEFAULT_SETTINGS}
        ctx.db.execute("UPDATE companies SET settings = ? WHERE id = ?",
                       (json.dumps(stored, ensure_ascii=False), ctx.cid))
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.settings.updated",
              detail={"changed": changed}, ip=ctx.req.ip)
    company = ctx.db.execute("SELECT * FROM companies WHERE id = ?", (ctx.cid,)).fetchone()
    return Response.json({"settings": company_settings(company),
                          "password_policy": passwords.policy_from_settings(company_settings(company))})


@router.route("GET", "/api/admin/mail", auth="admin")
def mail_log(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM mail_outbox WHERE company_id = ? ORDER BY id DESC LIMIT 100",
                          (ctx.cid,)).fetchall()
    return Response.json({"mail_mode": ctx.cfg.mail_mode, "messages": [{
        "id": r["id"], "to": r["to_addr"], "subject": r["subject"], "body": r["body"], "status": r["status"],
        "error": r["error"], "created_at": iso(r["created_at"])} for r in rows]})


# ------------------------------------------------------------------ わからんの森のカテゴリ

def _category_fields(ctx: Ctx, partial: bool) -> Dict[str, Any]:
    data = ctx.req.json()
    out: Dict[str, Any] = {}
    if not partial or "name" in data:
        out["name"] = ctx.req.str_field("name", label="カテゴリ名", max_len=30)
    if not partial or "emoji" in data:
        out["emoji"] = ctx.req.str_field("emoji", required=False, label="絵文字", max_len=8)
    if not partial or "description" in data:
        out["description"] = ctx.req.str_field("description", required=False, label="説明", max_len=200)
    if "position" in data:
        position = data.get("position")
        if not isinstance(position, int) or isinstance(position, bool) or not 0 <= position <= 999:
            raise ApiError(400, "invalid_field", "並び順は 0〜999 で指定してください", field="position")
        out["position"] = position
    return out


@router.route("GET", "/api/admin/forest-categories", auth="admin")
def forest_categories(ctx: Ctx) -> Response:
    from .forest import category_admin_json
    rows = ctx.db.execute("SELECT * FROM forest_categories WHERE company_id = ? ORDER BY position, id",
                          (ctx.cid,)).fetchall()
    return Response.json({"categories": [category_admin_json(ctx, r) for r in rows]})


@router.route("POST", "/api/admin/forest-categories", auth="admin")
def create_forest_category(ctx: Ctx) -> Response:
    from .forest import category_admin_json
    fields = _category_fields(ctx, partial=False)
    cur = ctx.db.execute("INSERT INTO forest_categories (company_id, name, emoji, description, position, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (ctx.cid, fields["name"], fields["emoji"],
                                                         fields["description"], fields.get("position", 100), now()))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.forest_category.created",
          target_type="forest_category", target_id=cur.lastrowid, detail=fields, ip=ctx.req.ip)
    row = ctx.db.execute("SELECT * FROM forest_categories WHERE id = ?", (cur.lastrowid,)).fetchone()
    return Response.json({"category": category_admin_json(ctx, row)})


@router.route("PATCH", "/api/admin/forest-categories/{id:int}", auth="admin")
def update_forest_category(ctx: Ctx) -> Response:
    from .forest import category_admin_json
    row = ctx.db.execute("SELECT * FROM forest_categories WHERE id = ? AND company_id = ?",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "カテゴリが見つかりません")
    fields = _category_fields(ctx, partial=True)
    if fields:
        sets = ", ".join("%s = ?" % k for k in fields)
        ctx.db.execute("UPDATE forest_categories SET %s WHERE id = ?" % sets, list(fields.values()) + [row["id"]])
        audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.forest_category.updated",
              target_type="forest_category", target_id=row["id"], detail=fields, ip=ctx.req.ip)
    row = ctx.db.execute("SELECT * FROM forest_categories WHERE id = ?", (row["id"],)).fetchone()
    return Response.json({"category": category_admin_json(ctx, row)})


# ------------------------------------------------------------------ AI インサイト（利用状況の集計と定性レポート）

MENTION_OR_EMAIL = re.compile(r"@[A-Za-z0-9._\-]+|[^\s@]+@[^\s@]+")


def _insight_stats(ctx: Ctx) -> Dict[str, Any]:
    db, cid = ctx.db, ctx.cid
    today = datetime.now(JST).replace(hour=0, minute=0, second=0, microsecond=0)
    start = today - timedelta(days=29)
    since = int(start.timestamp())

    def day(ts: int) -> str:
        return datetime.fromtimestamp(ts, JST).strftime("%Y-%m-%d")

    days = {(start + timedelta(days=i)).strftime("%Y-%m-%d"): {"posts": 0, "comments": 0, "users": set()}
            for i in range(30)}
    commit_channel = db.execute("SELECT id FROM channels WHERE company_id = ? AND system_kind = 'commit'",
                                (cid,)).fetchone()[0]
    posts = db.execute("SELECT p.*, c.name AS channel_name, c.system_kind FROM posts p JOIN channels c"
                       " ON c.id = p.channel_id WHERE p.company_id = ? AND p.created_at >= ? AND p.deleted_at IS NULL"
                       " AND p.kind != 'share'", (cid, since)).fetchall()
    comments = db.execute("SELECT * FROM comments WHERE company_id = ? AND created_at >= ? AND deleted_at IS NULL",
                          (cid, since)).fetchall()
    logins = db.execute("SELECT actor_id, created_at FROM audit_logs WHERE company_id = ? AND action ="
                        " 'auth.login.success' AND created_at >= ?", (cid, since)).fetchall()
    for p in posts:
        d = days.get(day(p["created_at"]))
        if d:
            d["posts"] += 1
            d["users"].add(p["author_id"])
    for cm in comments:
        d = days.get(day(cm["created_at"]))
        if d:
            d["comments"] += 1
            d["users"].add(cm["author_id"])
    for lg in logins:
        d = days.get(day(lg["created_at"]))
        if d and lg["actor_id"]:
            d["users"].add(lg["actor_id"])
    daily = [{"date": k, "posts": v["posts"], "comments": v["comments"], "active_users": len(v["users"])}
             for k, v in days.items()]

    members = db.execute("SELECT * FROM users WHERE company_id = ? AND status = 'active'", (cid,)).fetchall()
    ts_now = now()
    likes_by_post = {r[0]: r[1] for r in db.execute(
        "SELECT l.post_id, COUNT(*) FROM likes l JOIN posts p ON p.id = l.post_id WHERE p.company_id = ?"
        " AND p.created_at >= ? GROUP BY l.post_id", (cid, since))}
    comments_by_post: Dict[int, int] = {}
    for cm in comments:
        comments_by_post[cm["post_id"]] = comments_by_post.get(cm["post_id"], 0) + 1
    by_user_dept = {u["id"]: (u["department"] or "（部署なし）") for u in members}
    # アクティブ = 期間中にログイン・投稿・コメントのどれかをした人（全体の数字と同じ定義）
    active_ids = {uid for d in days.values() for uid in d["users"]}
    departments: Dict[str, Dict[str, Any]] = {}
    for u in members:
        dept = departments.setdefault(by_user_dept[u["id"]], {"members": 0, "active_30d": 0, "posts": 0, "comments": 0,
                                                               "likes_received": 0})
        dept["members"] += 1
        if u["id"] in active_ids:
            dept["active_30d"] += 1
    for p in posts:
        dept = departments.get(by_user_dept.get(p["author_id"], ""))
        if dept is not None:
            dept["posts"] += 1
            dept["likes_received"] += likes_by_post.get(p["id"], 0)
    for cm in comments:
        dept = departments.get(by_user_dept.get(cm["author_id"], ""))
        if dept is not None:
            dept["comments"] += 1
    channels: Dict[str, Dict[str, int]] = {}
    for p in posts:
        name = "COMMIT" if p["system_kind"] == "commit" else p["channel_name"]
        ch = channels.setdefault(name, {"posts": 0, "comments": 0, "likes": 0})
        ch["posts"] += 1
        ch["comments"] += comments_by_post.get(p["id"], 0)
        ch["likes"] += likes_by_post.get(p["id"], 0)

    silent = sorted(
        [{"id": u["id"], "display_name": u["display_name"], "department": u["department"],
          "days_since_login": None if not u["last_login_at"] else (ts_now - u["last_login_at"]) // 86400}
         for u in members if not u["last_login_at"] or u["last_login_at"] < ts_now - 14 * 86400],
        key=lambda x: (x["days_since_login"] is not None, -(x["days_since_login"] or 0)))

    ranked = sorted(posts, key=lambda p: -(likes_by_post.get(p["id"], 0) + 2 * comments_by_post.get(p["id"], 0)))
    top_posts = []
    for p in ranked[:5]:
        score = likes_by_post.get(p["id"], 0) + comments_by_post.get(p["id"], 0)
        if score == 0:
            break
        top_posts.append({"id": p["id"], "excerpt": p["body"].replace("\n", " ")[:120],
                          "channel": "COMMIT" if p["system_kind"] == "commit" else p["channel_name"],
                          "likes": likes_by_post.get(p["id"], 0), "comments": comments_by_post.get(p["id"], 0)})

    questions = db.execute("SELECT q.*, (SELECT MIN(a.created_at) FROM answers a WHERE a.question_id = q.id AND"
                           " a.deleted_at IS NULL) AS first_answer FROM questions q WHERE q.company_id = ? AND"
                           " q.deleted_at IS NULL", (cid,)).fetchall()
    recent_q = [q for q in questions if q["created_at"] >= since]
    waits = sorted((q["first_answer"] - q["created_at"]) / 3600 for q in recent_q if q["first_answer"])
    forest = {
        "questions_30d": len(recent_q),
        "answered_30d": len([q for q in recent_q if q["first_answer"]]),
        "unanswered_open": len([q for q in questions if not q["first_answer"]]),
        "median_hours_to_first_answer": round(waits[len(waits) // 2], 1) if waits else None,
    }
    active_7d = len({u for d in daily[-7:] for u in days[d["date"]]["users"]})
    active_30d = len({u for d in days.values() for u in d["users"]})
    return {
        "period": {"from": start.strftime("%Y-%m-%d"), "to": today.strftime("%Y-%m-%d")},
        "totals": {"members": len(members), "active_7d": active_7d, "active_30d": active_30d,
                   "posts_30d": len([p for p in posts if p["channel_id"] != commit_channel]),
                   "commits_30d": len([p for p in posts if p["channel_id"] == commit_channel]),
                   "comments_30d": len(comments), "likes_30d": sum(likes_by_post.values())},
        "daily": daily,
        "departments": [dict(name=k, **v) for k, v in sorted(departments.items())],
        "channels": [dict(name=k, **v) for k, v in sorted(channels.items(), key=lambda x: -x[1]["posts"])],
        "silent_users": silent[:50],
        "silent_count": len(silent),
        "top_posts": top_posts,
        "forest": forest,
    }


def _insight_digest(company_name: str, s: Dict[str, Any]) -> str:
    """AI に渡す文章。氏名・社員コード・メールアドレスは含めない。"""
    t = s["totals"]
    lines = ["# %s の社内 SNS 利用状況（%s 〜 %s）" % (company_name, s["period"]["from"], s["period"]["to"]), "",
             "## 全体",
             "- 在籍アカウント %d 人 / 直近 7 日にアクティブ %d 人 / 30 日にアクティブ %d 人"
             % (t["members"], t["active_7d"], t["active_30d"]),
             "- 30 日間: 投稿 %d 件、COMMIT %d 件、コメント %d 件、いいね %d 件"
             % (t["posts_30d"], t["commits_30d"], t["comments_30d"], t["likes_30d"]),
             "- 14 日以上ログインしていない人: %d 人" % s["silent_count"], "", "## 週ごとの推移"]
    for i in range(0, 30, 7):
        week = s["daily"][i:i + 7]
        lines.append("- %s〜: 投稿 %d / コメント %d / 1 日あたりのアクティブ人数（最大）%d" % (
            week[0]["date"], sum(d["posts"] for d in week), sum(d["comments"] for d in week),
            max(d["active_users"] for d in week)))
    lines += ["", "## 部署別（30 日）"]
    for d in s["departments"]:
        lines.append("- %s: %d 人中 %d 人がアクティブ、投稿 %d、コメント %d、受け取ったいいね %d" % (
            d["name"], d["members"], d["active_30d"], d["posts"], d["comments"], d["likes_received"]))
    lines += ["", "## チャンネル別（30 日）"]
    for c in s["channels"][:15]:
        lines.append("- %s: 投稿 %d、コメント %d、いいね %d" % (c["name"], c["posts"], c["comments"], c["likes"]))
    f = s["forest"]
    lines += ["", "## わからんの森（社内 Q&A）",
              "- 30 日間の質問 %d 件（うち回答あり %d 件）、未回答のまま残っている質問 %d 件"
              % (f["questions_30d"], f["answered_30d"], f["unanswered_open"]),
              "- 最初の回答までの時間（中央値）: %s" % (
                  "%s 時間" % f["median_hours_to_first_answer"] if f["median_hours_to_first_answer"] is not None
                  else "データなし")]
    lines += ["", "## 反応の多かった投稿（抜粋・氏名なし）"]
    for p in s["top_posts"]:
        lines.append("- [%s] 「%s」 いいね %d・コメント %d" % (
            p["channel"], MENTION_OR_EMAIL.sub("（伏せ字）", p["excerpt"]), p["likes"], p["comments"]))
    if not s["top_posts"]:
        lines.append("- （反応のある投稿はまだありません）")
    return "\n".join(lines)


def _report_json(r: sqlite3.Row) -> Dict[str, Any]:
    return {"id": r["id"], "provider": r["provider"], "model": r["model"], "content": r["content"],
            "input_tokens": r["input_tokens"], "output_tokens": r["output_tokens"], "created_at": iso(r["created_at"])}


@router.route("GET", "/api/admin/insights", auth="admin")
def insights(ctx: Ctx) -> Response:
    from . import ai
    reports = ctx.db.execute("SELECT * FROM insight_reports WHERE company_id = ? ORDER BY id DESC LIMIT 10",
                             (ctx.cid,)).fetchall()
    return Response.json({"stats": _insight_stats(ctx), "ai": ai.status(),
                          "reports": [_report_json(r) for r in reports]})


@router.route("POST", "/api/admin/insights/generate", auth="admin")
def generate_insight(ctx: Ctx) -> Response:
    from . import ai
    st = ai.status()
    if not st["configured"]:
        raise ApiError(400, "ai_not_configured", st["message"])
    ctx.app.rate.check("insight:%d" % ctx.cid, limit=5, window=3600)
    digest = _insight_digest(ctx.company["name"], _insight_stats(ctx))
    try:
        content, model, usage = ai.generate(digest)
    except ai.AIError as err:
        raise ApiError(502, "ai_failed", err.message)
    cur = ctx.db.execute("INSERT INTO insight_reports (company_id, provider, model, content, input_tokens,"
                         " output_tokens, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, st["provider"], model, content, usage["input_tokens"], usage["output_tokens"],
                          ctx.uid, now()))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="admin.insights.generated",
          detail={"provider": st["provider"], "model": model}, ip=ctx.req.ip)
    row = ctx.db.execute("SELECT * FROM insight_reports WHERE id = ?", (cur.lastrowid,)).fetchone()
    return Response.json({"report": _report_json(row)})
