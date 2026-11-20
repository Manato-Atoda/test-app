"""企業管理者向け API（社員アカウントの発行・管理、チャンネル、通報、監査ログ、設定）。

すべて role=admin かつ自分の企業（company_id）の範囲だけを扱う。
"""
from __future__ import annotations

import csv
import io
import json
import sqlite3
from typing import Any, Dict, List

from . import passwords
from .accounts import (account_state, insert_user, issuable, issue_credentials, revoke_sessions,
                       send_credentials_mail, user_summary, users_by_ids, validate_user_fields)
from .db import DEFAULT_SETTINGS, audit, company_settings, iso, jp_datetime, now
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
    return {"id": c["id"], "name": c["name"], "description": c["description"], "visibility": c["visibility"],
            "company_wide": bool(c["company_wide"]), "post_policy": c["post_policy"], "archived": bool(c["archived"]),
            "member_count": members, "created_at": iso(c["created_at"])}


def _channel_fields(ctx: Ctx, partial: bool) -> Dict[str, Any]:
    data = ctx.req.json()
    out: Dict[str, Any] = {}
    if not partial or "name" in data:
        out["name"] = ctx.req.str_field("name", label="チャンネル名", max_len=40)
    if not partial or "description" in data:
        out["description"] = ctx.req.str_field("description", required=False, label="説明", max_len=200)
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
    row = ctx.db.execute("SELECT * FROM channels WHERE id = ? AND company_id = ?",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "チャンネルが見つかりません")
    return row


@router.route("GET", "/api/admin/channels", auth="admin")
def admin_channels(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM channels WHERE company_id = ? ORDER BY archived, company_wide DESC,"
                          " sort_order, name", (ctx.cid,)).fetchall()
    return Response.json({"channels": [_admin_channel_json(ctx, c) for c in rows]})


@router.route("POST", "/api/admin/channels", auth="admin")
def create_channel(ctx: Ctx) -> Response:
    fields = _channel_fields(ctx, partial=False)
    if ctx.db.execute("SELECT 1 FROM channels WHERE company_id = ? AND name = ?", (ctx.cid, fields["name"])).fetchone():
        raise ApiError(409, "duplicate", "同じ名前のチャンネルがあります", field="name")
    cur = ctx.db.execute(
        "INSERT INTO channels (company_id, name, description, visibility, company_wide, post_policy, created_by,"
        " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (ctx.cid, fields["name"], fields["description"], fields["visibility"], fields["company_wide"],
         fields["post_policy"], ctx.uid, now()))
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
