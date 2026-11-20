"""SNS 本体（チャンネル・投稿・コメント・いいね・保存・シェア/引用・COMMIT・通知・バッジ・社員名簿・検索・通報）。

見られる範囲:
- 全社チャンネル（company_wide）… 全員
- 公開チャンネル（open）… 全員が閲覧・参加できる（投稿は参加後）
- 非公開チャンネル（private）… メンバーのみ
- COMMIT は企業ごとの見えないチャンネル（system_kind='commit'、全員）に入れる。一覧やホームには出さない

発信者（identity）が実名以外の投稿・コメントは、API で本人がわからない形にする（accounts.author_fields）。
"""
from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta
from typing import Any, Dict, Iterable, List, Optional

from .accounts import author_fields, resolve_identity, user_profile, user_summary
from .db import JST, QUICK_COMMENTS, audit, get_seen, iso, mark_seen, now
from .uploads import image_json, own_upload
from .web import ApiError, Ctx, Response, Router

router = Router()

POST_MAX = 4000
COMMENT_MAX = 2000
MAX_IMAGES = 4
MENTION_RE = re.compile(r"(?<![A-Za-z0-9._%+\-])@([A-Za-z0-9._\-]{1,32})")

# 利用者が見られるチャンネルの条件（c = channels, m = 自分の channel_members）
VISIBLE = "(c.company_wide = 1 OR c.visibility = 'open' OR m.user_id IS NOT NULL)"
JOINED = "(c.company_wide = 1 OR m.user_id IS NOT NULL)"
NOT_SYSTEM = "c.system_kind IS NULL"
LIVE = "p.deleted_at IS NULL AND p.hidden_at IS NULL"
POST_FROM = ("FROM posts p JOIN channels c ON c.id = p.channel_id"
             " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?")


def _marks(values: Iterable[Any]) -> str:
    return ",".join("?" * len(list(values)))


def _excerpt(text: str, length: int = 80) -> str:
    text = (text or "").replace("\n", " ").strip()
    return text if len(text) <= length else text[:length] + "…"


# ------------------------------------------------------------------ チャンネル

def _channel_row(ctx: Ctx, channel_id: Any, allow_system: bool = False) -> sqlite3.Row:
    row = ctx.db.execute(
        "SELECT c.*, m.user_id AS my_membership FROM channels c"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE c.id = ? AND c.company_id = ? AND " + VISIBLE + ("" if allow_system else " AND " + NOT_SYSTEM),
        (ctx.uid, channel_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "チャンネルが見つかりません")
    return row


def commit_channel(ctx: Ctx) -> sqlite3.Row:
    row = ctx.db.execute("SELECT c.*, NULL AS my_membership FROM channels c WHERE c.company_id = ?"
                         " AND c.system_kind = 'commit'", (ctx.cid,)).fetchone()
    assert row is not None, "COMMIT のチャンネルがありません（db.ensure_company_defaults）"
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


def _unread_count(ctx: Ctx, c: sqlite3.Row) -> int:
    if not _is_member(c):
        return 0
    seen = get_seen(ctx.db, ctx.uid, "channel-%d" % c["id"])
    return ctx.db.execute("SELECT COUNT(*) FROM posts p WHERE p.channel_id = ? AND " + LIVE +
                          " AND p.author_id != ? AND p.created_at >= ? AND p.kind != 'share'",
                          (c["id"], ctx.uid, seen)).fetchone()[0]


def channel_json(ctx: Ctx, c: sqlite3.Row) -> Dict[str, Any]:
    return {
        "id": c["id"], "name": c["name"], "emoji": c["emoji"], "description": c["description"],
        "visibility": c["visibility"], "company_wide": bool(c["company_wide"]), "post_policy": c["post_policy"],
        "archived": bool(c["archived"]), "is_member": _is_member(c), "can_post": _can_post(ctx, c),
        "member_count": _member_count(ctx, c), "unread_count": _unread_count(ctx, c),
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
        " WHERE c.company_id = ? AND c.archived = 0 AND " + VISIBLE + " AND " + NOT_SYSTEM +
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

def users_by_id(db: sqlite3.Connection, ids: Iterable[int]) -> Dict[int, sqlite3.Row]:
    ids = list(set(i for i in ids if i is not None))
    if not ids:
        return {}
    return {r["id"]: r for r in db.execute("SELECT * FROM users WHERE id IN (%s)" % _marks(ids), ids).fetchall()}


def _counts(ctx: Ctx, sql: str, ids: List[int], with_mine: bool = True) -> Dict[int, tuple]:
    if not ids:
        return {}
    args: List[Any] = ([ctx.uid] if with_mine else []) + ids
    return {r[0]: (r[1], bool(r[2]) if with_mine else False) for r in ctx.db.execute(sql % _marks(ids), args)}


def serialize_posts(ctx: Ctx, rows: List[sqlite3.Row], with_quote: bool = True) -> List[Dict[str, Any]]:
    if not rows:
        return []
    ids = [r["id"] for r in rows]
    marks = _marks(ids)
    authors = users_by_id(ctx.db, (r["author_id"] for r in rows))
    channel_ids = list({r["channel_id"] for r in rows})
    channels = {r["id"]: r for r in ctx.db.execute(
        "SELECT id, name, emoji, system_kind FROM channels WHERE id IN (%s)" % _marks(channel_ids), channel_ids)}
    likes = _counts(ctx, "SELECT post_id, COUNT(*), SUM(user_id = ?) FROM likes WHERE post_id IN (%s) GROUP BY post_id", ids)
    acks = _counts(ctx, "SELECT post_id, COUNT(*), SUM(user_id = ?) FROM acks WHERE post_id IN (%s) GROUP BY post_id", ids)
    shares = _counts(ctx, "SELECT quote_of, COUNT(*), SUM(author_id = ?) FROM posts WHERE quote_of IN (%s)"
                          " AND kind = 'share' AND deleted_at IS NULL GROUP BY quote_of", ids)
    views = _counts(ctx, "SELECT post_id, COUNT(*), 0 FROM post_views WHERE post_id IN (%s) GROUP BY post_id",
                    ids, with_mine=False)
    comments = {r[0]: r[1] for r in ctx.db.execute(
        "SELECT post_id, COUNT(*) FROM comments WHERE post_id IN (%s) AND deleted_at IS NULL AND hidden_at IS NULL"
        " GROUP BY post_id" % marks, ids)}
    bookmarked = {r[0] for r in ctx.db.execute(
        "SELECT post_id FROM bookmarks WHERE user_id = ? AND post_id IN (%s)" % marks, [ctx.uid] + ids)}

    image_ids: List[str] = []
    for r in rows:
        image_ids.extend(json.loads(r["images"] or "[]"))
    images = {r["id"]: image_json(r) for r in ctx.db.execute(
        "SELECT * FROM uploads WHERE id IN (%s)" % _marks(image_ids), image_ids)} if image_ids else {}

    quoted: Dict[int, Dict[str, Any]] = {}
    if with_quote:
        quote_ids = list({r["quote_of"] for r in rows if r["quote_of"]})
        if quote_ids:
            qrows = ctx.db.execute("SELECT p.* FROM posts p WHERE p.id IN (%s) AND p.company_id = ? AND " % _marks(quote_ids)
                                   + LIVE, quote_ids + [ctx.cid]).fetchall()
            quoted = {q["id"]: q for q in serialize_posts(ctx, qrows, with_quote=False)}

    out = []
    for r in rows:
        ch = channels[r["channel_id"]]
        mine = r["author_id"] == ctx.uid
        like_count, liked = likes.get(r["id"], (0, False))
        ack_count, acked = acks.get(r["id"], (0, False))
        share_count, shared = shares.get(r["id"], (0, False))
        item = {
            "id": r["id"],
            "kind": r["kind"],
            "channel": None if ch["system_kind"] else {"id": ch["id"], "name": ch["name"], "emoji": ch["emoji"]},
            "body": r["body"],
            "images": [images[i] for i in json.loads(r["images"] or "[]") if i in images],
            "quote_of": quoted.get(r["quote_of"]) if r["quote_of"] else None,
            "require_ack": bool(r["require_ack"]),
            "acked_by_me": acked,
            "ack_count": ack_count,
            "like_count": like_count,
            "liked_by_me": liked,
            "comment_count": comments.get(r["id"], 0),
            "share_count": share_count,
            "shared_by_me": shared,
            "bookmarked_by_me": r["id"] in bookmarked,
            "view_count": views.get(r["id"], (0, False))[0],
            "created_at": iso(r["created_at"]),
            "edited_at": iso(r["edited_at"]),
            "can_edit": mine and r["kind"] != "share",
            "can_delete": mine or ctx.is_admin,
        }
        item.update(author_fields(r, authors.get(r["author_id"]), ctx.uid))
        out.append(item)
    return out


def _visible_post(ctx: Ctx, post_id: Any) -> sqlite3.Row:
    row = ctx.db.execute("SELECT p.* " + POST_FROM + " WHERE p.id = ? AND p.company_id = ? AND " + LIVE +
                         " AND " + VISIBLE, (ctx.uid, post_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "投稿が見つかりません（削除されたか、閲覧できないチャンネルです）")
    return row


def _target_post(ctx: Ctx, post_id: Any) -> sqlite3.Row:
    """シェア（そのままシェア）に対する操作は、シェア元の投稿に対して行う。"""
    post = _visible_post(ctx, post_id)
    if post["kind"] == "share" and post["quote_of"]:
        return _visible_post(ctx, post["quote_of"])
    return post


def _post_response(ctx: Ctx, post_id: int) -> Response:
    return Response.json({"post": serialize_posts(ctx, [_visible_post(ctx, post_id)])[0]})


def _body(ctx: Ctx, max_len: int, required: bool = True, field: str = "body") -> str:
    body = ctx.req.json().get(field)
    if body is None:
        body = ""
    if not isinstance(body, str):
        raise ApiError(400, "invalid_field", "本文の形式が正しくありません", field=field)
    body = body.replace("\r\n", "\n").replace("\r", "\n").strip()
    if required and not body:
        raise ApiError(400, "required", "本文を入力してください", field=field)
    if len(body) > max_len:
        raise ApiError(400, "too_long", "本文は%d文字以内にしてください" % max_len, field=field)
    return body


def _image_ids(ctx: Ctx) -> List[str]:
    ids = ctx.req.json().get("image_ids") or []
    if not isinstance(ids, list) or len(ids) > MAX_IMAGES:
        raise ApiError(400, "too_many_images", "画像は%d枚までです" % MAX_IMAGES)
    return [own_upload(ctx, i)["id"] for i in ids]


# ------------------------------------------------------------------ 通知

def notify(db: sqlite3.Connection, company_id: int, user_ids: Iterable[int], kind: str, actor_id: int, *,
           post_id: Optional[int] = None, comment_id: Optional[int] = None, question_id: Optional[int] = None,
           answer_id: Optional[int] = None, actor_name: Optional[str] = None) -> None:
    """actor_name があるとき（実名以外の発信）は、通知を受けた人に実名を見せない。"""
    ts = now()
    db.executemany(
        "INSERT INTO notifications (company_id, user_id, type, actor_id, post_id, comment_id, question_id,"
        " answer_id, actor_name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [(company_id, uid, kind, actor_id, post_id, comment_id, question_id, answer_id, actor_name, ts)
         for uid in set(user_ids) if uid != actor_id])


def mentioned_ids(ctx: Ctx, body: str, audience: Optional[List[int]] = None) -> List[int]:
    codes = {m.group(1).rstrip(".") for m in MENTION_RE.finditer(body)}
    codes.discard("")
    if not codes:
        return []
    codes_list = list(codes)[:20]
    rows = ctx.db.execute("SELECT id FROM users WHERE company_id = ? AND status = 'active' AND employee_code IN (%s)"
                          % _marks(codes_list), [ctx.cid] + codes_list).fetchall()
    ids = [r[0] for r in rows]
    if audience is None:
        return ids
    allowed = set(audience)
    return [i for i in ids if i in allowed]


def _channel_mentions(ctx: Ctx, body: str, channel: sqlite3.Row) -> List[int]:
    if channel["company_wide"] or channel["visibility"] == "open":
        return mentioned_ids(ctx, body)
    return mentioned_ids(ctx, body, audience_ids(ctx.db, channel))


# ------------------------------------------------------------------ タイムライン・投稿

def _page(rows: List[sqlite3.Row], limit: int) -> tuple:
    has_more = len(rows) > limit
    rows = rows[:limit]
    return rows, (rows[-1]["id"] if has_more and rows else None)


@router.route("GET", "/api/feed")
def feed(ctx: Ctx) -> Response:
    req = ctx.req
    limit = req.int_query("limit", 20, lo=1, hi=50) or 20
    before = req.int_query("before")
    after = req.int_query("after")
    channel_id = req.int_query("channel_id")
    where = ["p.company_id = ?", LIVE, NOT_SYSTEM]
    args: List[Any] = [ctx.uid, ctx.cid]
    if channel_id:
        _channel_row(ctx, channel_id)  # 閲覧権限の確認
        where.append("p.channel_id = ?")
        args.append(channel_id)
    else:
        where.append(JOINED)
    if req.query.get("kind") == "announcement":
        where.append("p.kind = 'announcement'")
    if after:
        where.append("p.id > ?")
        args.append(after)
        limit = 50
    if before:
        where.append("p.id < ?")
        args.append(before)
    rows = ctx.db.execute("SELECT p.* " + POST_FROM + " WHERE " + " AND ".join(where) +
                          " ORDER BY p.id DESC LIMIT ?", args + [limit + 1]).fetchall()
    rows, next_before = _page(rows, limit)
    return Response.json({"posts": serialize_posts(ctx, rows), "next_before": None if after else next_before})


def _insert_post(ctx: Ctx, *, channel: sqlite3.Row, body: str, kind: str, require_ack: bool = False,
                 identity: str = "real", display_name: Optional[str] = None, images: Optional[List[str]] = None,
                 quote_of: Optional[int] = None) -> int:
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute(
        "INSERT INTO posts (company_id, channel_id, author_id, body, kind, require_ack, identity, display_name,"
        " images, quote_of, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (ctx.cid, channel["id"], ctx.uid, body, kind, int(require_ack), identity, display_name,
         json.dumps(images or []), quote_of, now()))
    return int(cur.lastrowid)


def _shareable(ctx: Ctx, post: sqlite3.Row) -> sqlite3.Row:
    """シェア・引用できるか確認し、入れるチャンネルを返す（元の投稿と同じ。見られる人が広がらないように）。"""
    channel = _channel_row(ctx, post["channel_id"], allow_system=True)
    if channel["archived"]:
        raise ApiError(403, "forbidden", "アーカイブされたチャンネルの投稿はシェアできません")
    if channel["post_policy"] == "admins" and not ctx.is_admin:
        raise ApiError(403, "forbidden", "このチャンネルの投稿はシェア・引用できません")
    return channel


@router.route("POST", "/api/posts")
def create_post(ctx: Ctx) -> Response:
    data = ctx.req.json()
    kind = data.get("kind") or "post"
    require_ack = bool(data.get("require_ack"))
    if kind not in ("post", "announcement"):
        raise ApiError(400, "invalid_field", "投稿の種類が正しくありません")
    if (kind == "announcement" or require_ack) and not ctx.is_admin:
        raise ApiError(403, "forbidden", "お知らせを投稿できるのは管理者だけです")
    if require_ack and kind != "announcement":
        raise ApiError(400, "invalid_field", "確認ボタンはお知らせにだけ付けられます")
    images = _image_ids(ctx)
    quote = None
    if data.get("quote_of") is not None:
        quote = _target_post(ctx, data.get("quote_of") if isinstance(data.get("quote_of"), int) else -1)
        channel = _shareable(ctx, quote)
        if kind != "post":
            raise ApiError(400, "invalid_field", "お知らせで引用はできません")
    else:
        channel = _channel_row(ctx, data.get("channel_id") if isinstance(data.get("channel_id"), int) else -1)
        if not _can_post(ctx, channel):
            raise ApiError(403, "forbidden", "このチャンネルには投稿できません")
    body = _body(ctx, POST_MAX, required=not images and quote is None)
    identity, display_name = ("real", None) if kind == "announcement" else \
        resolve_identity(ctx.db, ctx.user, ctx.company, data.get("identity"))
    post_id = _insert_post(ctx, channel=channel, body=body, kind=kind, require_ack=require_ack, identity=identity,
                           display_name=display_name, images=images, quote_of=quote["id"] if quote else None)
    actor_name = display_name
    mentioned = _channel_mentions(ctx, body, channel)
    if kind == "announcement":
        notify(ctx.db, ctx.cid, [u for u in audience_ids(ctx.db, channel) if u not in mentioned],
               "announcement", ctx.uid, post_id=post_id)
    notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, post_id=post_id, actor_name=actor_name)
    if quote is not None and quote["author_id"] not in mentioned:
        notify(ctx.db, ctx.cid, [quote["author_id"]], "quote", ctx.uid, post_id=post_id, actor_name=actor_name)
    _delete_draft(ctx, data.get("draft_id"))
    return _post_response(ctx, post_id)


@router.route("GET", "/api/posts/{id:int}")
def get_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    return Response.json({"post": serialize_posts(ctx, [post])[0], "comments": _comments_json(ctx, post["id"])})


@router.route("PATCH", "/api/posts/{id:int}")
def edit_post(ctx: Ctx) -> Response:
    post = _visible_post(ctx, ctx.req.params["id"])
    if post["author_id"] != ctx.uid or post["kind"] == "share":
        raise ApiError(403, "forbidden", "自分の投稿だけ編集できます")
    body = _body(ctx, POST_MAX, required=not json.loads(post["images"] or "[]") and not post["quote_of"])
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


# ------------------------------------------------------------------ いいね・保存・シェア・閲覧

@router.route("PUT", "/api/posts/{id:int}/like")
def like(ctx: Ctx) -> Response:
    post = _target_post(ctx, ctx.req.params["id"])
    ctx.db.execute("INSERT OR IGNORE INTO likes (post_id, user_id, created_at) VALUES (?, ?, ?)",
                   (post["id"], ctx.uid, now()))
    return _post_response(ctx, post["id"])


@router.route("DELETE", "/api/posts/{id:int}/like")
def unlike(ctx: Ctx) -> Response:
    post = _target_post(ctx, ctx.req.params["id"])
    ctx.db.execute("DELETE FROM likes WHERE post_id = ? AND user_id = ?", (post["id"], ctx.uid))
    return _post_response(ctx, post["id"])


@router.route("PUT", "/api/posts/{id:int}/bookmark")
def bookmark(ctx: Ctx) -> Response:
    post = _target_post(ctx, ctx.req.params["id"])
    ctx.db.execute("INSERT OR IGNORE INTO bookmarks (post_id, user_id, created_at) VALUES (?, ?, ?)",
                   (post["id"], ctx.uid, now()))
    return _post_response(ctx, post["id"])


@router.route("DELETE", "/api/posts/{id:int}/bookmark")
def unbookmark(ctx: Ctx) -> Response:
    post = _target_post(ctx, ctx.req.params["id"])
    ctx.db.execute("DELETE FROM bookmarks WHERE post_id = ? AND user_id = ?", (post["id"], ctx.uid))
    return _post_response(ctx, post["id"])


@router.route("POST", "/api/posts/{id:int}/share")
def share(ctx: Ctx) -> Response:
    original = _target_post(ctx, ctx.req.params["id"])
    channel = _shareable(ctx, original)
    existing = ctx.db.execute("SELECT id FROM posts WHERE quote_of = ? AND author_id = ? AND kind = 'share'"
                              " AND deleted_at IS NULL", (original["id"], ctx.uid)).fetchone()
    if existing:
        return _post_response(ctx, existing["id"])
    post_id = _insert_post(ctx, channel=channel, body="", kind="share", quote_of=original["id"])
    notify(ctx.db, ctx.cid, [original["author_id"]], "share", ctx.uid, post_id=original["id"])
    return _post_response(ctx, post_id)


@router.route("DELETE", "/api/posts/{id:int}/share")
def unshare(ctx: Ctx) -> Response:
    original = _target_post(ctx, ctx.req.params["id"])
    ctx.db.execute("UPDATE posts SET deleted_at = ?, deleted_by = ? WHERE quote_of = ? AND author_id = ?"
                   " AND kind = 'share' AND deleted_at IS NULL", (now(), ctx.uid, original["id"], ctx.uid))
    return _post_response(ctx, original["id"])


@router.route("POST", "/api/posts/views")
def record_views(ctx: Ctx) -> Response:
    ids = ctx.req.json().get("ids")
    if not isinstance(ids, list):
        raise ApiError(400, "invalid_field", "ids を指定してください")
    ids = [i for i in ids if isinstance(i, int)][:100]
    if ids:
        visible = [r[0] for r in ctx.db.execute(
            "SELECT p.id " + POST_FROM + " WHERE p.company_id = ? AND p.id IN (%s) AND " % _marks(ids) + VISIBLE,
            [ctx.uid, ctx.cid] + ids)]
        ts = now()
        ctx.db.executemany("INSERT OR IGNORE INTO post_views (post_id, user_id, created_at) VALUES (?, ?, ?)",
                           [(i, ctx.uid, ts) for i in visible])
    return Response.empty()


@router.route("GET", "/api/bookmarks")
def bookmarks(ctx: Ctx) -> Response:
    kind = ctx.req.query.get("kind") or "post"
    before = ctx.req.int_query("before")
    # before は bookmarks の保存日時（UNIX 秒）
    sql = ("SELECT p.*, b.created_at AS bookmarked_at " + POST_FROM.replace("FROM posts p", "FROM bookmarks b JOIN posts p ON p.id = b.post_id") +
           " WHERE b.user_id = ? AND p.company_id = ? AND " + LIVE + " AND " + VISIBLE +
           (" AND c.system_kind = 'commit'" if kind == "commit" else " AND " + NOT_SYSTEM))
    args: List[Any] = [ctx.uid, ctx.uid, ctx.cid]
    if before:
        sql += " AND b.created_at < ?"
        args.append(before)
    rows = ctx.db.execute(sql + " ORDER BY b.created_at DESC LIMIT 31", args).fetchall()
    has_more = len(rows) > 30
    rows = rows[:30]
    return Response.json({"posts": serialize_posts(ctx, rows),
                          "next_before": rows[-1]["bookmarked_at"] if has_more and rows else None})


# ------------------------------------------------------------------ コメント

def _comments_json(ctx: Ctx, post_id: int, only_id: Optional[int] = None) -> List[Dict[str, Any]]:
    sql = "SELECT * FROM comments WHERE post_id = ? AND deleted_at IS NULL"
    args: List[Any] = [post_id]
    if only_id is not None:
        sql += " AND id = ?"
        args.append(only_id)
    rows = ctx.db.execute(sql + " ORDER BY id", args).fetchall()
    ids = [r["id"] for r in rows]
    likes = _counts(ctx, "SELECT comment_id, COUNT(*), SUM(user_id = ?) FROM comment_likes WHERE comment_id IN (%s)"
                         " GROUP BY comment_id", ids)
    authors = users_by_id(ctx.db, (r["author_id"] for r in rows))
    out = []
    for r in rows:
        hidden = bool(r["hidden_at"])
        like_count, liked = likes.get(r["id"], (0, False))
        item = {
            "id": r["id"], "post_id": r["post_id"], "body": "" if hidden else r["body"], "hidden": hidden,
            "is_quick": bool(r["is_quick"]), "like_count": like_count, "liked_by_me": liked,
            "created_at": iso(r["created_at"]), "edited_at": iso(r["edited_at"]),
            "can_edit": r["author_id"] == ctx.uid and not hidden,
            "can_delete": (r["author_id"] == ctx.uid or ctx.is_admin) and not hidden,
        }
        item.update(author_fields(r, authors.get(r["author_id"]), ctx.uid))
        out.append(item)
    return out


def _comment_row(ctx: Ctx) -> sqlite3.Row:
    row = ctx.db.execute("SELECT * FROM comments WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "コメントが見つかりません")
    _visible_post(ctx, row["post_id"])
    return row


def _comment_response(ctx: Ctx, row: sqlite3.Row) -> Response:
    return Response.json({"comment": _comments_json(ctx, row["post_id"], only_id=row["id"])[0]})


@router.route("POST", "/api/posts/{id:int}/comments")
def create_comment(ctx: Ctx) -> Response:
    post = _target_post(ctx, ctx.req.params["id"])
    channel = _channel_row(ctx, post["channel_id"], allow_system=True)
    if channel["archived"]:
        raise ApiError(403, "forbidden", "アーカイブされたチャンネルにはコメントできません")
    data = ctx.req.json()
    quick = data.get("quick_index")
    if quick is not None:
        if not isinstance(quick, int) or not 0 <= quick < len(QUICK_COMMENTS):
            raise ApiError(400, "invalid_field", "定型コメントの指定が正しくありません")
        body = "%s %s" % (QUICK_COMMENTS[quick]["emoji"], QUICK_COMMENTS[quick]["text"])
    else:
        body = _body(ctx, COMMENT_MAX)
    identity, display_name = resolve_identity(ctx.db, ctx.user, ctx.company, data.get("identity"))
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO comments (company_id, post_id, author_id, body, identity, display_name, is_quick,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, post["id"], ctx.uid, body, identity, display_name, int(quick is not None), now()))
    comment_id = int(cur.lastrowid)
    mentioned = _channel_mentions(ctx, body, channel)
    notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, post_id=post["id"], comment_id=comment_id,
           actor_name=display_name)
    if post["author_id"] not in mentioned:
        notify(ctx.db, ctx.cid, [post["author_id"]], "comment", ctx.uid, post_id=post["id"], comment_id=comment_id,
               actor_name=display_name)
    return _comment_response(ctx, ctx.db.execute("SELECT * FROM comments WHERE id = ?", (comment_id,)).fetchone())


@router.route("PATCH", "/api/comments/{id:int}")
def edit_comment(ctx: Ctx) -> Response:
    row = _comment_row(ctx)
    if row["author_id"] != ctx.uid or row["hidden_at"]:
        raise ApiError(403, "forbidden", "自分のコメントだけ編集できます")
    body = _body(ctx, COMMENT_MAX)
    ctx.db.execute("UPDATE comments SET body = ?, edited_at = ?, is_quick = 0 WHERE id = ?", (body, now(), row["id"]))
    return _comment_response(ctx, row)


@router.route("DELETE", "/api/comments/{id:int}")
def delete_comment(ctx: Ctx) -> Response:
    row = _comment_row(ctx)
    if row["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "このコメントは削除できません")
    ctx.db.execute("UPDATE comments SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, row["id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="comment.deleted", target_type="comment",
          target_id=row["id"], detail={"by_admin": row["author_id"] != ctx.uid}, ip=ctx.req.ip)
    return Response.empty()


@router.route("PUT", "/api/comments/{id:int}/like")
def like_comment(ctx: Ctx) -> Response:
    row = _comment_row(ctx)
    ctx.db.execute("INSERT OR IGNORE INTO comment_likes (comment_id, user_id, created_at) VALUES (?, ?, ?)",
                   (row["id"], ctx.uid, now()))
    return _comment_response(ctx, row)


@router.route("DELETE", "/api/comments/{id:int}/like")
def unlike_comment(ctx: Ctx) -> Response:
    row = _comment_row(ctx)
    ctx.db.execute("DELETE FROM comment_likes WHERE comment_id = ? AND user_id = ?", (row["id"], ctx.uid))
    return _comment_response(ctx, row)


# ------------------------------------------------------------------ お知らせの確認

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
    users = users_by_id(ctx.db, audience + list(acked))
    ordered = sorted(users.values(), key=lambda u: (u["department"], u["employee_code"]))
    return Response.json({
        "acked": [user_summary(u) for u in ordered if u["id"] in acked],
        "not_acked": [user_summary(u) for u in ordered if u["id"] not in acked and u["status"] == "active"],
    })


# ------------------------------------------------------------------ 下書き

def _delete_draft(ctx: Ctx, draft_id: Any) -> None:
    if isinstance(draft_id, int):
        ctx.db.execute("DELETE FROM drafts WHERE id = ? AND user_id = ?", (draft_id, ctx.uid))


def _draft_json(r: sqlite3.Row) -> Dict[str, Any]:
    return {"id": r["id"], "body": r["body"], "identity": r["identity"], "channel_id": r["channel_id"],
            "updated_at": iso(r["updated_at"])}


@router.route("GET", "/api/drafts")
def list_drafts(ctx: Ctx) -> Response:
    rows = ctx.db.execute("SELECT * FROM drafts WHERE user_id = ? ORDER BY updated_at DESC LIMIT 20",
                          (ctx.uid,)).fetchall()
    return Response.json({"drafts": [_draft_json(r) for r in rows]})


@router.route("POST", "/api/drafts")
def save_draft(ctx: Ctx) -> Response:
    data = ctx.req.json()
    body = _body(ctx, POST_MAX)
    identity = data.get("identity") if data.get("identity") in ("real", "department", "anonymous") else "real"
    channel_id = data.get("channel_id") if isinstance(data.get("channel_id"), int) else None
    if ctx.db.execute("SELECT COUNT(*) FROM drafts WHERE user_id = ?", (ctx.uid,)).fetchone()[0] >= 20:
        raise ApiError(400, "too_many", "下書きは20件までです。使わないものを削除してください")
    ts = now()
    cur = ctx.db.execute("INSERT INTO drafts (user_id, body, identity, channel_id, created_at, updated_at)"
                         " VALUES (?, ?, ?, ?, ?, ?)", (ctx.uid, body, identity, channel_id, ts, ts))
    return Response.json({"draft": _draft_json(ctx.db.execute("SELECT * FROM drafts WHERE id = ?",
                                                              (cur.lastrowid,)).fetchone())})


@router.route("DELETE", "/api/drafts/{id:int}")
def delete_draft(ctx: Ctx) -> Response:
    _delete_draft(ctx, ctx.req.params["id"])
    return Response.empty()


# ------------------------------------------------------------------ COMMIT

def _period_start(period: str) -> Optional[int]:
    today = datetime.now(JST).replace(hour=0, minute=0, second=0, microsecond=0)
    if period == "today":
        return int(today.timestamp())
    if period == "week":
        return int((today - timedelta(days=today.weekday())).timestamp())
    if period == "month":
        return int(today.replace(day=1).timestamp())
    return None


@router.route("GET", "/api/commits")
def list_commits(ctx: Ctx) -> Response:
    channel = commit_channel(ctx)
    sql = "SELECT p.* FROM posts p WHERE p.channel_id = ? AND " + LIVE
    args: List[Any] = [channel["id"]]
    user_id = ctx.req.int_query("user_id")
    if user_id:
        sql += " AND p.author_id = ? AND p.identity = 'real'"
        args.append(user_id)
    start = _period_start(ctx.req.query.get("period") or "all")
    if start is not None:
        sql += " AND p.created_at >= ?"
        args.append(start)
    before = ctx.req.int_query("before")
    if before:
        sql += " AND p.id < ?"
        args.append(before)
    rows = ctx.db.execute(sql + " ORDER BY p.id DESC LIMIT 21", args).fetchall()
    rows, next_before = _page(rows, 20)
    return Response.json({"posts": serialize_posts(ctx, rows), "next_before": next_before})


@router.route("POST", "/api/commits")
def create_commit(ctx: Ctx) -> Response:
    images = _image_ids(ctx)
    body = _body(ctx, POST_MAX)
    post_id = _insert_post(ctx, channel=commit_channel(ctx), body=body, kind="commit", images=images)
    notify(ctx.db, ctx.cid, mentioned_ids(ctx, body), "mention", ctx.uid, post_id=post_id)
    return _post_response(ctx, post_id)


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
    rows, next_before = _page(rows, limit)
    actors = users_by_id(ctx.db, (r["actor_id"] for r in rows if r["actor_id"] and not r["actor_name"]))

    def bodies(table: str, ids: List[int], column: str = "body") -> Dict[int, sqlite3.Row]:
        ids = list({i for i in ids if i})
        if not ids:
            return {}
        return {r["id"]: r for r in ctx.db.execute(
            "SELECT id, %s AS text, deleted_at FROM %s WHERE id IN (%s)" % (column, table, _marks(ids)), ids)}

    posts = bodies("posts", [r["post_id"] for r in rows])
    comments = bodies("comments", [r["comment_id"] for r in rows])
    questions = bodies("questions", [r["question_id"] for r in rows], "title")
    answers = bodies("answers", [r["answer_id"] for r in rows])
    items = []
    for r in rows:
        source = (comments.get(r["comment_id"]) or answers.get(r["answer_id"]) or posts.get(r["post_id"])
                  or questions.get(r["question_id"]))
        excerpt = _excerpt(source["text"]) if source is not None and not source["deleted_at"] else ""
        actor = actors.get(r["actor_id"]) if not r["actor_name"] else None
        target = {"type": "question", "id": r["question_id"]} if r["question_id"] else \
            ({"type": "post", "id": r["post_id"]} if r["post_id"] else None)
        items.append({"id": r["id"], "type": r["type"], "actor": user_summary(actor) if actor else None,
                      "actor_name": r["actor_name"], "post_id": r["post_id"], "target": target,
                      "excerpt": excerpt, "created_at": iso(r["created_at"]), "read": r["read_at"] is not None})
    unread = ctx.db.execute("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at IS NULL",
                            (ctx.uid,)).fetchone()[0]
    return Response.json({"notifications": items, "unread_count": unread, "next_before": next_before})


@router.route("POST", "/api/notifications/read-all")
def read_all(ctx: Ctx) -> Response:
    ctx.db.execute("UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL", (now(), ctx.uid))
    return Response.empty()


@router.route("POST", "/api/notifications/{id:int}/read")
def read_one(ctx: Ctx) -> Response:
    ctx.db.execute("UPDATE notifications SET read_at = ? WHERE id = ? AND user_id = ? AND read_at IS NULL",
                   (now(), ctx.req.params["id"], ctx.uid))
    return Response.empty()


# ------------------------------------------------------------------ バッジ・既読・右側の欄

SEEN_KEY = re.compile(r"^(home|forest|commit|channel-\d{1,18})$")


@router.route("POST", "/api/seen/{key}")
def seen(ctx: Ctx) -> Response:
    key = str(ctx.req.params["key"])
    if not SEEN_KEY.match(key):
        raise ApiError(400, "invalid_field", "既読にする画面の指定が正しくありません")
    mark_seen(ctx.db, ctx.uid, key)
    return Response.empty()


def forest_urgency(age_seconds: Optional[int]) -> str:
    if age_seconds is None or age_seconds < 6 * 3600:
        return "calm"
    if age_seconds < 24 * 3600:
        return "soft"
    if age_seconds < 72 * 3600:
        return "warm"
    return "hot"


def oldest_unanswered_by_others(ctx: Ctx) -> Optional[int]:
    row = ctx.db.execute(
        "SELECT MIN(q.created_at) FROM questions q WHERE q.company_id = ? AND q.deleted_at IS NULL"
        " AND q.author_id != ? AND NOT EXISTS (SELECT 1 FROM answers a WHERE a.question_id = q.id"
        " AND a.deleted_at IS NULL)", (ctx.cid, ctx.uid)).fetchone()
    return row[0]


@router.route("GET", "/api/badges")
def badges(ctx: Ctx) -> Response:
    db = ctx.db
    unread = db.execute("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at IS NULL",
                        (ctx.uid,)).fetchone()[0]
    forest_new = db.execute("SELECT 1 FROM questions WHERE company_id = ? AND deleted_at IS NULL AND author_id != ?"
                            " AND created_at >= ? LIMIT 1",
                            (ctx.cid, ctx.uid, get_seen(db, ctx.uid, "forest"))).fetchone() is not None
    oldest = oldest_unanswered_by_others(ctx)
    commit_new = db.execute("SELECT 1 FROM posts p WHERE p.channel_id = ? AND " + LIVE +
                            " AND p.author_id != ? AND p.created_at >= ? LIMIT 1",
                            (commit_channel(ctx)["id"], ctx.uid, get_seen(db, ctx.uid, "commit"))).fetchone() is not None
    unacked = db.execute(
        "SELECT COUNT(*) " + POST_FROM + " WHERE p.company_id = ? AND " + LIVE + " AND " + JOINED +
        " AND p.require_ack = 1 AND p.author_id != ? AND NOT EXISTS (SELECT 1 FROM acks a WHERE a.post_id = p.id"
        " AND a.user_id = ?)", (ctx.uid, ctx.cid, ctx.uid, ctx.uid)).fetchone()[0]
    channels = db.execute(
        "SELECT c.*, m.user_id AS my_membership FROM channels c"
        " LEFT JOIN channel_members m ON m.channel_id = c.id AND m.user_id = ?"
        " WHERE c.company_id = ? AND c.archived = 0 AND " + JOINED + " AND " + NOT_SYSTEM, (ctx.uid, ctx.cid)).fetchall()
    return Response.json({
        "notifications": unread,
        "forest_has_new": forest_new,
        "forest_urgency": forest_urgency(now() - oldest if oldest else None),
        "commit_has_new": commit_new,
        "announcements_unacked": unacked,
        "channels_unread": sum(_unread_count(ctx, c) for c in channels),
    })


@router.route("GET", "/api/highlights")
def highlights(ctx: Ctx) -> Response:
    db = ctx.db
    today = _period_start("today") or 0
    week = now() - 7 * 86400
    members = db.execute(
        "SELECT u.*, MAX(COALESCE(u.last_login_at, 0), COALESCE((SELECT MAX(created_at) FROM posts p"
        " WHERE p.author_id = u.id AND p.identity = 'real'), 0)) AS active_at"
        " FROM users u WHERE u.company_id = ? AND u.status = 'active'", (ctx.cid,)).fetchall()
    members_today = sorted([u for u in members if u["active_at"] >= today], key=lambda u: -u["active_at"])[:12]
    active_7d = len([u for u in members if u["active_at"] >= week])
    trending_rows = db.execute(
        "SELECT p.*, (SELECT COUNT(*) FROM likes l WHERE l.post_id = p.id) AS lc,"
        " (SELECT COUNT(*) FROM comments cm WHERE cm.post_id = p.id AND cm.deleted_at IS NULL) AS cc " + POST_FROM +
        " WHERE p.company_id = ? AND " + LIVE + " AND " + VISIBLE + " AND p.created_at >= ? AND p.kind != 'share'"
        " ORDER BY (lc + cc * 2) DESC, p.id DESC LIMIT 5", (ctx.uid, ctx.cid, week)).fetchall()
    authors = users_by_id(db, (r["author_id"] for r in trending_rows))
    trending = []
    for r in trending_rows:
        if r["lc"] + r["cc"] == 0:
            continue
        a = author_fields(r, authors.get(r["author_id"]), ctx.uid)
        trending.append({"id": r["id"], "excerpt": _excerpt(r["body"], 60) or "（画像）",
                         "display_name": a["author"]["display_name"] if a["author"] else a["display_name"],
                         "like_count": r["lc"], "comment_count": r["cc"]})
    since = now() - 14 * 86400
    reactions: List[Dict[str, Any]] = []
    for r in db.execute("SELECT l.post_id, l.created_at, p.body FROM likes l JOIN posts p ON p.id = l.post_id"
                        " WHERE p.author_id = ? AND l.user_id != ? AND l.created_at >= ? AND " + LIVE +
                        " ORDER BY l.created_at DESC LIMIT 10", (ctx.uid, ctx.uid, since)):
        # いいねは誰が押したかを出さない
        reactions.append({"type": "like", "actor": None, "display_name": None, "post_id": r["post_id"],
                          "excerpt": _excerpt(r["body"], 40), "created_at": r["created_at"]})
    comment_rows = db.execute(
        "SELECT cm.*, p.body AS post_body FROM comments cm JOIN posts p ON p.id = cm.post_id WHERE p.author_id = ?"
        " AND cm.author_id != ? AND cm.created_at >= ? AND cm.deleted_at IS NULL AND cm.hidden_at IS NULL AND " + LIVE +
        " ORDER BY cm.created_at DESC LIMIT 10", (ctx.uid, ctx.uid, since)).fetchall()
    commenters = users_by_id(db, (r["author_id"] for r in comment_rows))
    for r in comment_rows:
        a = author_fields(r, commenters.get(r["author_id"]), ctx.uid)
        reactions.append({"type": "comment", "actor": a["author"], "display_name": a["display_name"],
                          "post_id": r["post_id"], "excerpt": _excerpt(r["body"], 40), "created_at": r["created_at"]})
    reactions.sort(key=lambda x: -x["created_at"])
    for x in reactions:
        x["created_at"] = iso(x["created_at"])
    return Response.json({"members_today": [user_summary(u) for u in members_today], "active_7d": active_7d,
                          "trending": trending, "recent_reactions": reactions[:10]})


# ------------------------------------------------------------------ 社員名簿・プロフィール・検索

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
    from .forest import questions_json  # 循環 import を避ける
    user = ctx.db.execute("SELECT * FROM users WHERE id = ? AND company_id = ?",
                          (ctx.req.params["id"], ctx.cid)).fetchone()
    if user is None:
        raise ApiError(404, "not_found", "見つかりません")
    # 実名のものだけ（匿名・部署名の投稿をプロフィールに並べると、誰の発信かわかってしまう）
    base = ("SELECT p.* " + POST_FROM + " WHERE p.company_id = ? AND p.author_id = ? AND p.identity = 'real' AND "
            + LIVE + " AND " + VISIBLE)
    posts = ctx.db.execute(base + " AND " + NOT_SYSTEM + " AND p.kind != 'share' ORDER BY p.id DESC LIMIT 20",
                           (ctx.uid, ctx.cid, user["id"])).fetchall()
    commits = ctx.db.execute(base + " AND c.system_kind = 'commit' AND p.kind = 'commit' ORDER BY p.id DESC LIMIT 20",
                             (ctx.uid, ctx.cid, user["id"])).fetchall()
    questions = ctx.db.execute("SELECT * FROM questions WHERE company_id = ? AND author_id = ? AND identity = 'real'"
                               " AND deleted_at IS NULL ORDER BY id DESC LIMIT 20", (ctx.cid, user["id"])).fetchall()
    return Response.json({"user": user_profile(user), "posts": serialize_posts(ctx, posts),
                          "commits": serialize_posts(ctx, commits), "questions": questions_json(ctx, questions)})


@router.route("GET", "/api/search")
def search(ctx: Ctx) -> Response:
    q = (ctx.req.query.get("q") or "").strip()[:100]
    if not q:
        return Response.json({"posts": []})
    rows = ctx.db.execute(
        "SELECT p.* " + POST_FROM + " WHERE p.company_id = ? AND " + LIVE + " AND " + VISIBLE +
        " AND p.kind != 'share' AND p.body LIKE ? ESCAPE '\\' ORDER BY p.id DESC LIMIT 30",
        (ctx.uid, ctx.cid, _like(q))).fetchall()
    return Response.json({"posts": serialize_posts(ctx, rows)})
