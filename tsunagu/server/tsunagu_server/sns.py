"""SNS 本体（チャンネル・投稿・コメント・リアクション・お知らせの確認・通知・社員名簿・検索・通報）。

見られる範囲:
- 全社チャンネル（company_wide）… 全員
- 公開チャンネル（open）… 全員が閲覧・参加できる（投稿は参加後）
- 非公開チャンネル（private）… メンバーのみ
"""
from __future__ import annotations

import re
import sqlite3
from typing import Any, Dict, Iterable, List, Optional

from .accounts import user_profile, user_summary
from .db import audit, iso, now
from .web import ApiError, Ctx, Response, Router

router = Router()

REACTIONS = ("like", "thanks", "clap", "celebrate", "idea", "eyes")
POST_MAX = 4000
COMMENT_MAX = 2000
MENTION_RE = re.compile(r"(?<![A-Za-z0-9._%+\-])@([A-Za-z0-9._\-]{1,32})")

# 利用者が見られるチャンネルの条件（c = channels, m = 自分の channel_members）
VISIBLE = "(c.company_wide = 1 OR c.visibility = 'open' OR m.user_id IS NOT NULL)"
JOINED = "(c.company_wide = 1 OR m.user_id IS NOT NULL)"


def _marks(values: Iterable[Any]) -> str:
    return ",".join("?" * len(list(values)))


# ------------------------------------------------------------------ チャンネル

def _channel_row(ctx: Ctx, channel_id: Any) -> sqlite3.Row:
    row = ctx.db.execute(
        "SELECT c.*, m.user_id AS my_membership FROM channels c"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE c.id = ? AND c.company_id = ? AND " + VISIBLE, (ctx.uid, channel_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "チャンネルが見つかりません")
    return row


def _is_member(c: sqlite3.Row) -> bool:
    return bool(c["company_wide"]) or c["my_membership"] is not None


def _can_post(ctx: Ctx, c: sqlite3.Row) -> bool:
    return _is_member(c) and not c["archived"] and (c["post_policy"] == "everyone" or ctx.is_admin)


def _member_count(ctx: Ctx, c: sqlite3.Row) -> int:
    if c["company_wide"]:
        return ctx.db.execute("SELECT COUNT(*) FROM users WHERE company_id = ? AND status = 'active'",
                              (ctx.cid,)).fetchone()[0]
    return ctx.db.execute("SELECT COUNT(*) FROM channel_members cm JOIN users u ON u.id = cm.user_id"
                          " WHERE cm.channel_id = ? AND u.status = 'active'", (c["id"],)).fetchone()[0]


def channel_json(ctx: Ctx, c: sqlite3.Row) -> Dict[str, Any]:
    return {
        "id": c["id"], "name": c["name"], "description": c["description"], "visibility": c["visibility"],
        "company_wide": bool(c["company_wide"]), "post_policy": c["post_policy"], "archived": bool(c["archived"]),
        "is_member": _is_member(c), "can_post": _can_post(ctx, c), "member_count": _member_count(ctx, c),
    }


def audience_ids(db: sqlite3.Connection, channel: sqlite3.Row) -> List[int]:
    if channel["company_wide"]:
        rows = db.execute("SELECT id FROM users WHERE company_id = ? AND status = 'active'",
                          (channel["company_id"],)).fetchall()
    else:
        rows = db.execute("SELECT u.id FROM channel_members cm JOIN users u ON u.id = cm.user_id"
                          " WHERE cm.channel_id = ? AND u.status = 'active'", (channel["id"],)).fetchall()
    return [r[0] for r in rows]


@router.route("GET", "/api/channels")
def list_channels(ctx: Ctx) -> Response:
    rows = ctx.db.execute(
        "SELECT c.*, m.user_id AS my_membership FROM channels c"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE c.company_id = ? AND c.archived = 0 AND " + VISIBLE +
        " ORDER BY c.company_wide DESC, c.sort_order, c.name", (ctx.uid, ctx.cid)).fetchall()
    return Response.json({"channels": [channel_json(ctx, c) for c in rows]})


@router.route("GET", "/api/channels/{id:int}")
def get_channel(ctx: Ctx) -> Response:
    return Response.json({"channel": channel_json(ctx, _channel_row(ctx, ctx.req.params["id"]))})


@router.route("POST", "/api/channels/{id:int}/join")
def join_channel(ctx: Ctx) -> Response:
    c = _channel_row(ctx, ctx.req.params["id"])
    if c["company_wide"] or c["archived"]:
        raise ApiError(400, "not_allowed", "このチャンネルには参加・退出の操作はできません")
    ctx.db.execute("INSERT OR IGNORE INTO channel_members (channel_id, user_id, joined_at) VALUES (?, ?, ?)",
                   (c["id"], ctx.uid, now()))
    return Response.json({"channel": channel_json(ctx, _channel_row(ctx, c["id"]))})


@router.route("POST", "/api/channels/{id:int}/leave")
def leave_channel(ctx: Ctx) -> Response:
    c = _channel_row(ctx, ctx.req.params["id"])
    if c["company_wide"]:
        raise ApiError(400, "not_allowed", "全社チャンネルからは退出できません")
    if c["visibility"] == "private":
        raise ApiError(400, "not_allowed", "非公開チャンネルの退出は管理者に依頼してください")
    ctx.db.execute("DELETE FROM channel_members WHERE channel_id = ? AND user_id = ?", (c["id"], ctx.uid))
    return Response.json({"channel": channel_json(ctx, _channel_row(ctx, c["id"]))})


# ------------------------------------------------------------------ 投稿の整形

def _users_by_id(db: sqlite3.Connection, ids: Iterable[int]) -> Dict[int, sqlite3.Row]:
    ids = list(set(ids))
    if not ids:
        return {}
    return {r["id"]: r for r in db.execute("SELECT * FROM users WHERE id IN (%s)" % _marks(ids), ids).fetchall()}


def serialize_posts(ctx: Ctx, rows: List[sqlite3.Row]) -> List[Dict[str, Any]]:
    if not rows:
        return []
    ids = [r["id"] for r in rows]
    marks = _marks(ids)
    authors = _users_by_id(ctx.db, (r["author_id"] for r in rows))
    channels = {r["id"]: r for r in ctx.db.execute(
        "SELECT id, name FROM channels WHERE id IN (%s)" % _marks({r["channel_id"] for r in rows}),
        list({r["channel_id"] for r in rows})).fetchall()}
    reactions: Dict[int, List[Dict[str, Any]]] = {}
    for r in ctx.db.execute("SELECT post_id, reaction, COUNT(*) AS n, SUM(user_id = ?) AS mine FROM reactions"
                            " WHERE post_id IN (%s) GROUP BY post_id, reaction" % marks, [ctx.uid] + ids):
        reactions.setdefault(r["post_id"], []).append(
            {"key": r["reaction"], "count": r["n"], "reacted_by_me": bool(r["mine"])})
    comments = {r[0]: r[1] for r in ctx.db.execute(
        "SELECT post_id, COUNT(*) FROM comments WHERE post_id IN (%s) AND deleted_at IS NULL AND hidden_at IS NULL"
        " GROUP BY post_id" % marks, ids)}
    acks = {r[0]: (r[1], bool(r[2])) for r in ctx.db.execute(
        "SELECT post_id, COUNT(*), SUM(user_id = ?) FROM acks WHERE post_id IN (%s) GROUP BY post_id" % marks,
        [ctx.uid] + ids)}
    out = []
    for r in rows:
        order = {k: i for i, k in enumerate(REACTIONS)}
        ack_count, acked = acks.get(r["id"], (0, False))
        mine = r["author_id"] == ctx.uid
        out.append({
            "id": r["id"],
            "channel": {"id": r["channel_id"], "name": channels[r["channel_id"]]["name"]},
            "author": user_summary(authors[r["author_id"]]),
            "body": r["body"],
            "kind": r["kind"],
            "require_ack": bool(r["require_ack"]),
            "acked_by_me": acked,
            "ack_count": ack_count,
            "reactions": sorted(reactions.get(r["id"], []), key=lambda x: order.get(x["key"], 99)),
            "comment_count": comments.get(r["id"], 0),
            "created_at": iso(r["created_at"]),
            "edited_at": iso(r["edited_at"]),
            "can_edit": mine,
            "can_delete": mine or ctx.is_admin,
        })
    return out


def _visible_post(ctx: Ctx, post_id: Any) -> sqlite3.Row:
    row = ctx.db.execute(
        "SELECT p.* FROM posts p JOIN channels c ON c.id = p.channel_id"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE p.id = ? AND p.company_id = ? AND p.deleted_at IS NULL AND p.hidden_at IS NULL AND " + VISIBLE,
        (ctx.uid, post_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "投稿が見つかりません（削除されたか、閲覧できないチャンネルです）")
    return row


def _post_response(ctx: Ctx, post_id: int) -> Response:
    return Response.json({"post": serialize_posts(ctx, [_visible_post(ctx, post_id)])[0]})


def _body(ctx: Ctx, max_len: int) -> str:
    body = ctx.req.json().get("body")
    if not isinstance(body, str):
        raise ApiError(400, "required", "本文を入力してください", field="body")
    body = body.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not body:
        raise ApiError(400, "required", "本文を入力してください", field="body")
    if len(body) > max_len:
        raise ApiError(400, "too_long", "本文は%d文字以内にしてください" % max_len, field="body")
    return body


# ------------------------------------------------------------------ 通知

def _notify(db: sqlite3.Connection, company_id: int, user_ids: Iterable[int], kind: str, actor_id: int,
            post_id: int, comment_id: Optional[int] = None) -> None:
    ts = now()
    db.executemany("INSERT INTO notifications (company_id, user_id, type, actor_id, post_id, comment_id, created_at)"
                   " VALUES (?, ?, ?, ?, ?, ?, ?)",
                   [(company_id, uid, kind, actor_id, post_id, comment_id, ts) for uid in set(user_ids)
                    if uid != actor_id])


def _mentioned_ids(ctx: Ctx, body: str, channel: sqlite3.Row) -> List[int]:
    codes = {m.group(1).rstrip(".") for m in MENTION_RE.finditer(body)}
    codes.discard("")
    if not codes:
        return []
    codes_list = list(codes)[:20]
    rows = ctx.db.execute("SELECT id FROM users WHERE company_id = ? AND status = 'active' AND employee_code IN (%s)"
                          % _marks(codes_list), [ctx.cid] + codes_list).fetchall()
    ids = [r[0] for r in rows]
    if channel["company_wide"] or channel["visibility"] == "open":
        return ids
    members = set(audience_ids(ctx.db, channel))
    return [i for i in ids if i in members]


# ------------------------------------------------------------------ タイムライン・投稿

@router.route("GET", "/api/feed")
def feed(ctx: Ctx) -> Response:
    req = ctx.req
    limit = req.int_query("limit", 20, lo=1, hi=50) or 20
    before = req.int_query("before")
    channel_id = req.int_query("channel_id")
    where = ["p.company_id = ?", "p.deleted_at IS NULL", "p.hidden_at IS NULL"]
    args: List[Any] = [ctx.uid, ctx.cid]
    if channel_id:
        _channel_row(ctx, channel_id)  # 閲覧権限の確認
        where.append("p.channel_id = ?")
        args.append(channel_id)
    else:
        where.append(JOINED)
    if req.query.get("kind") == "announcement":
        where.append("p.kind = 'announcement'")
    if before:
        where.append("p.id < ?")
        args.append(before)
    rows = ctx.db.execute(
        "SELECT p.* FROM posts p JOIN channels c ON c.id = p.channel_id"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE " + " AND ".join(where) + " ORDER BY p.id DESC LIMIT ?", args + [limit + 1]).fetchall()
    has_more = len(rows) > limit
    rows = rows[:limit]
    return Response.json({"posts": serialize_posts(ctx, rows),
                          "next_before": rows[-1]["id"] if has_more and rows else None})


@router.route("POST", "/api/posts")
def create_post(ctx: Ctx) -> Response:
    data = ctx.req.json()
    channel = _channel_row(ctx, data.get("channel_id") if isinstance(data.get("channel_id"), int) else -1)
    if not _can_post(ctx, channel):
        raise ApiError(403, "forbidden", "このチャンネルには投稿できません")
    body = _body(ctx, POST_MAX)
    kind = data.get("kind") or "post"
    require_ack = bool(data.get("require_ack"))
    if kind not in ("post", "announcement"):
        raise ApiError(400, "invalid_field", "投稿の種類が正しくありません")
    if (kind == "announcement" or require_ack) and not ctx.is_admin:
        raise ApiError(403, "forbidden", "お知らせを投稿できるのは管理者だけです")
    if require_ack and kind != "announcement":
        raise ApiError(400, "invalid_field", "確認ボタンはお知らせにだけ付けられます")
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO posts (company_id, channel_id, author_id, body, kind, require_ack, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, channel["id"], ctx.uid, body, kind, int(require_ack), now()))
    post_id = int(cur.lastrowid)
    mentioned = _mentioned_ids(ctx, body, channel)
    if kind == "announcement":
        _notify(ctx.db, ctx.cid, [u for u in audience_ids(ctx.db, channel) if u not in mentioned],
                "announcement", ctx.uid, post_id)
    _notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, post_id)
    return _post_response(ctx, post_id)


@router.route("GET", "/api/posts/{id:int}")
def get_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    rows = ctx.db.execute("SELECT * FROM comments WHERE post_id = ? AND deleted_at IS NULL ORDER BY id",
                          (post["id"],)).fetchall()
    authors = _users_by_id(ctx.db, (r["author_id"] for r in rows))
    comments = [{
        "id": r["id"], "post_id": r["post_id"], "author": user_summary(authors[r["author_id"]]),
        "body": "" if r["hidden_at"] else r["body"], "hidden": bool(r["hidden_at"]),
        "created_at": iso(r["created_at"]),
        "can_delete": (r["author_id"] == ctx.uid or ctx.is_admin) and not r["hidden_at"],
    } for r in rows]
    return Response.json({"post": serialize_posts(ctx, [post])[0], "comments": comments})


@router.route("PATCH", "/api/posts/{id:int}")
def edit_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    if post["author_id"] != ctx.uid:
        raise ApiError(403, "forbidden", "自分の投稿だけ編集できます")
    body = _body(ctx, POST_MAX)
    if body != post["body"]:
        ts = now()
        ctx.db.execute("INSERT INTO post_revisions (post_id, body, edited_by, edited_at) VALUES (?, ?, ?, ?)",
                       (post["id"], post["body"], ctx.uid, ts))
        ctx.db.execute("UPDATE posts SET body = ?, edited_at = ? WHERE id = ?", (body, ts, post["id"]))
    return _post_response(ctx, post["id"])


@router.route("DELETE", "/api/posts/{id:int}")
def delete_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    if post["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "この投稿は削除できません")
    ctx.db.execute("UPDATE posts SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, post["id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="post.deleted", target_type="post",
          target_id=post["id"], detail={"by_admin": post["author_id"] != ctx.uid}, ip=ctx.req.ip)
    return Response.empty()


# ------------------------------------------------------------------ コメント・リアクション・確認

@router.route("POST", "/api/posts/{id:int}/comments")
def create_comment(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    channel = _channel_row(ctx, post["channel_id"])
    if channel["archived"]:
        raise ApiError(403, "forbidden", "アーカイブされたチャンネルにはコメントできません")
    body = _body(ctx, COMMENT_MAX)
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO comments (company_id, post_id, author_id, body, created_at)"
                         " VALUES (?, ?, ?, ?, ?)", (ctx.cid, post["id"], ctx.uid, body, now()))
    comment_id = int(cur.lastrowid)
    mentioned = _mentioned_ids(ctx, body, channel)
    _notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, post["id"], comment_id)
    if post["author_id"] not in mentioned:
        _notify(ctx.db, ctx.cid, [post["author_id"]], "comment", ctx.uid, post["id"], comment_id)
    r = ctx.db.execute("SELECT * FROM comments WHERE id = ?", (comment_id,)).fetchone()
    return Response.json({"comment": {
        "id": r["id"], "post_id": r["post_id"], "author": user_summary(ctx.user), "body": r["body"],
        "hidden": False, "created_at": iso(r["created_at"]), "can_delete": True}})


@router.route("DELETE", "/api/comments/{id:int}")
def delete_comment(ctx: Ctx) -> Response:
    row = ctx.db.execute("SELECT * FROM comments WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "コメントが見つかりません")
    _visible_post(ctx, row["post_id"])
    if row["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "このコメントは削除できません")
    ctx.db.execute("UPDATE comments SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, row["id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="comment.deleted", target_type="comment",
          target_id=row["id"], detail={"by_admin": row["author_id"] != ctx.uid}, ip=ctx.req.ip)
    return Response.empty()


def _reaction_key(ctx: Ctx) -> str:
    key = ctx.req.params["key"]
    if key not in REACTIONS:
        raise ApiError(400, "invalid_reaction", "そのリアクションは使えません")
    return key


@router.route("PUT", "/api/posts/{id:int}/reactions/{key}")
def add_reaction(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    ctx.db.execute("INSERT OR IGNORE INTO reactions (post_id, user_id, reaction, created_at) VALUES (?, ?, ?, ?)",
                   (post["id"], ctx.uid, _reaction_key(ctx), now()))
    return _post_response(ctx, post["id"])


@router.route("DELETE", "/api/posts/{id:int}/reactions/{key}")
def remove_reaction(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    ctx.db.execute("DELETE FROM reactions WHERE post_id = ? AND user_id = ? AND reaction = ?",
                   (post["id"], ctx.uid, _reaction_key(ctx)))
    return _post_response(ctx, post["id"])


@router.route("POST", "/api/posts/{id:int}/ack")
def ack_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    if not post["require_ack"]:
        raise ApiError(400, "not_allowed", "この投稿には確認ボタンがありません")
    ctx.db.execute("INSERT OR IGNORE INTO acks (post_id, user_id, created_at) VALUES (?, ?, ?)",
                   (post["id"], ctx.uid, now()))
    return _post_response(ctx, post["id"])


@router.route("GET", "/api/posts/{id:int}/acks")
def ack_status(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    if post["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "確認状況を見られるのは投稿者と管理者だけです")
    channel = ctx.db.execute("SELECT * FROM channels WHERE id = ?", (post["channel_id"],)).fetchone()
    audience = audience_ids(ctx.db, channel)
    acked = {r[0] for r in ctx.db.execute("SELECT user_id FROM acks WHERE post_id = ?", (post["id"],))}
    users = _users_by_id(ctx.db, audience + list(acked))
    ordered = sorted(users.values(), key=lambda u: (u["department"], u["employee_code"]))
    return Response.json({
        "acked": [user_summary(u) for u in ordered if u["id"] in acked],
        "not_acked": [user_summary(u) for u in ordered if u["id"] not in acked and u["status"] == "active"],
    })


# ------------------------------------------------------------------ 通報

@router.route("POST", "/api/reports")
def create_report(ctx: Ctx) -> Response:
    data = ctx.req.json()
    target_type = data.get("target_type")
    target_id = data.get("target_id")
    if target_type not in ("post", "comment") or not isinstance(target_id, int):
        raise ApiError(400, "invalid_field", "通報の対象が正しくありません")
    reason = ctx.req.str_field("reason", label="通報の理由", max_len=500)
    if target_type == "post":
        _visible_post(ctx, target_id)
    else:
        comment = ctx.db.execute("SELECT post_id FROM comments WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                                 (target_id, ctx.cid)).fetchone()
        if comment is None:
            raise ApiError(404, "not_found", "コメントが見つかりません")
        _visible_post(ctx, comment["post_id"])
    existing = ctx.db.execute("SELECT id FROM reports WHERE company_id = ? AND target_type = ? AND target_id = ?"
                              " AND reporter_id = ? AND status = 'open'",
                              (ctx.cid, target_type, target_id, ctx.uid)).fetchone()
    if existing:
        return Response.json({"report_id": existing["id"]})
    cur = ctx.db.execute("INSERT INTO reports (company_id, target_type, target_id, reporter_id, reason, created_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (ctx.cid, target_type, target_id, ctx.uid, reason, now()))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="report.created", target_type=target_type,
          target_id=target_id, ip=ctx.req.ip)
    return Response.json({"report_id": cur.lastrowid})


# ------------------------------------------------------------------ 通知

@router.route("GET", "/api/notifications")
def notifications(ctx: Ctx) -> Response:
    before = ctx.req.int_query("before")
    limit = 30
    args: List[Any] = [ctx.uid]
    sql = "SELECT * FROM notifications WHERE user_id = ?"
    if before:
        sql += " AND id < ?"
        args.append(before)
    rows = ctx.db.execute(sql + " ORDER BY id DESC LIMIT ?", args + [limit + 1]).fetchall()
    has_more = len(rows) > limit
    rows = rows[:limit]
    actors = _users_by_id(ctx.db, (r["actor_id"] for r in rows if r["actor_id"]))
    post_ids = list({r["post_id"] for r in rows if r["post_id"]})
    comment_ids = list({r["comment_id"] for r in rows if r["comment_id"]})
    posts = {r["id"]: r for r in ctx.db.execute(
        "SELECT id, body, deleted_at, hidden_at FROM posts WHERE id IN (%s)" % _marks(post_ids), post_ids)} \
        if post_ids else {}
    comments = {r["id"]: r for r in ctx.db.execute(
        "SELECT id, body, deleted_at, hidden_at FROM comments WHERE id IN (%s)" % _marks(comment_ids),
        comment_ids)} if comment_ids else {}
    items = []
    for r in rows:
        source = comments.get(r["comment_id"]) or posts.get(r["post_id"])
        excerpt = ""
        if source is not None and not source["deleted_at"] and not source["hidden_at"]:
            excerpt = source["body"].replace("\n", " ")[:80]
        actor = actors.get(r["actor_id"])
        items.append({"id": r["id"], "type": r["type"], "actor": user_summary(actor) if actor else None,
                      "post_id": r["post_id"], "excerpt": excerpt, "created_at": iso(r["created_at"]),
                      "read": r["read_at"] is not None})
    unread = ctx.db.execute("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at IS NULL",
                            (ctx.uid,)).fetchone()[0]
    return Response.json({"notifications": items, "unread_count": unread,
                          "next_before": rows[-1]["id"] if has_more and rows else None})


@router.route("POST", "/api/notifications/read-all")
def read_all(ctx: Ctx) -> Response:
    ctx.db.execute("UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL", (now(), ctx.uid))
    return Response.empty()


@router.route("POST", "/api/notifications/{id:int}/read")
def read_one(ctx: Ctx) -> Response:
    ctx.db.execute("UPDATE notifications SET read_at = ? WHERE id = ? AND user_id = ? AND read_at IS NULL",
                   (now(), ctx.req.params["id"], ctx.uid))
    return Response.empty()


# ------------------------------------------------------------------ 社員名簿・検索

def _like(q: str) -> str:
    return "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


@router.route("GET", "/api/directory")
def directory(ctx: Ctx) -> Response:
    q = (ctx.req.query.get("q") or "").strip()[:60]
    sql = "SELECT * FROM users WHERE company_id = ? AND status = 'active'"
    args: List[Any] = [ctx.cid]
    if q:
        sql += (" AND (display_name LIKE ? ESCAPE '\\' OR employee_code LIKE ? ESCAPE '\\'"
                " OR department LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR email LIKE ? ESCAPE '\\')")
        args += [_like(q)] * 5
    rows = ctx.db.execute(sql + " ORDER BY department, employee_code LIMIT 500", args).fetchall()
    return Response.json({"users": [user_profile(r) for r in rows]})


@router.route("GET", "/api/users/{id:int}")
def get_user(ctx: Ctx) -> Response:
    user = ctx.db.execute("SELECT * FROM users WHERE id = ? AND company_id = ?",
                          (ctx.req.params["id"], ctx.cid)).fetchone()
    if user is None:
        raise ApiError(404, "not_found", "見つかりません")
    rows = ctx.db.execute(
        "SELECT p.* FROM posts p JOIN channels c ON c.id = p.channel_id"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE p.company_id = ? AND p.author_id = ? AND p.deleted_at IS NULL AND p.hidden_at IS NULL AND " + VISIBLE +
        " ORDER BY p.id DESC LIMIT 20", (ctx.uid, ctx.cid, user["id"])).fetchall()
    return Response.json({"user": user_profile(user), "posts": serialize_posts(ctx, rows)})


@router.route("GET", "/api/search")
def search(ctx: Ctx) -> Response:
    q = (ctx.req.query.get("q") or "").strip()[:100]
    if not q:
        return Response.json({"posts": []})
    rows = ctx.db.execute(
        "SELECT p.* FROM posts p JOIN channels c ON c.id = p.channel_id"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE p.company_id = ? AND p.deleted_at IS NULL AND p.hidden_at IS NULL AND " + VISIBLE +
        " AND p.body LIKE ? ESCAPE '\\' ORDER BY p.id DESC LIMIT 30", (ctx.uid, ctx.cid, _like(q))).fetchall()
    return Response.json({"posts": serialize_posts(ctx, rows)})
