"""わからんの森（社内 Q&A）。

カテゴリごとに質問を投げかけ、だれでも回答・回答へのコメントができる。
発信者（実名・部署名・匿名）は投稿と同じ扱い。答え待ちの質問が古くなるほど、森のタブの印が強くなる。
"""
from __future__ import annotations

import sqlite3
from typing import Any, Dict, List, Optional

from .accounts import author_fields, resolve_identity
from .db import audit, iso, now
from .sns import _counts, _marks, _page, forest_urgency, mentioned_ids, notify, oldest_unanswered_by_others, users_by_id
from .web import ApiError, Ctx, Response, Router

router = Router()

TITLE_MAX = 120
BODY_MAX = 4000
ANSWER_MAX = 4000
COMMENT_MAX = 1000


def _text(ctx: Ctx, name: str, label: str, max_len: int, required: bool = True) -> str:
    value = ctx.req.json().get(name)
    value = "" if value is None else value
    if not isinstance(value, str):
        raise ApiError(400, "invalid_field", "%sの形式が正しくありません" % label, field=name)
    value = value.replace("\r\n", "\n").strip()
    if required and not value:
        raise ApiError(400, "required", "%sを入力してください" % label, field=name)
    if len(value) > max_len:
        raise ApiError(400, "too_long", "%sは%d文字以内にしてください" % (label, max_len), field=name)
    return value


# ------------------------------------------------------------------ 整形

def _categories(ctx: Ctx) -> Dict[int, sqlite3.Row]:
    return {r["id"]: r for r in ctx.db.execute("SELECT * FROM forest_categories WHERE company_id = ?", (ctx.cid,))}


def questions_json(ctx: Ctx, rows: List[sqlite3.Row]) -> List[Dict[str, Any]]:
    if not rows:
        return []
    ids = [r["id"] for r in rows]
    cats = _categories(ctx)
    authors = users_by_id(ctx.db, (r["author_id"] for r in rows))
    answers = {r[0]: r[1] for r in ctx.db.execute(
        "SELECT question_id, COUNT(*) FROM answers WHERE question_id IN (%s) AND deleted_at IS NULL"
        " GROUP BY question_id" % _marks(ids), ids)}
    views = {r[0]: r[1] for r in ctx.db.execute(
        "SELECT question_id, COUNT(*) FROM question_views WHERE question_id IN (%s) GROUP BY question_id"
        % _marks(ids), ids)}
    out = []
    for r in rows:
        cat = cats.get(r["category_id"])
        item = {
            "id": r["id"],
            "category": {"id": cat["id"], "name": cat["name"], "emoji": cat["emoji"]} if cat else None,
            "title": r["title"], "body": r["body"],
            "answer_count": answers.get(r["id"], 0), "view_count": views.get(r["id"], 0),
            "created_at": iso(r["created_at"]),
            "can_delete": r["author_id"] == ctx.uid or ctx.is_admin,
        }
        item.update(author_fields(r, authors.get(r["author_id"]), ctx.uid))
        out.append(item)
    return out


def _answers_json(ctx: Ctx, rows: List[sqlite3.Row]) -> List[Dict[str, Any]]:
    if not rows:
        return []
    ids = [r["id"] for r in rows]
    likes = _counts(ctx, "SELECT answer_id, COUNT(*), SUM(user_id = ?) FROM answer_likes WHERE answer_id IN (%s)"
                         " GROUP BY answer_id", ids)
    comment_rows = ctx.db.execute("SELECT * FROM answer_comments WHERE answer_id IN (%s) AND deleted_at IS NULL"
                                  " ORDER BY id" % _marks(ids), ids).fetchall()
    authors = users_by_id(ctx.db, [r["author_id"] for r in rows] + [c["author_id"] for c in comment_rows])
    comments: Dict[int, List[Dict[str, Any]]] = {}
    for c in comment_rows:
        item = {"id": c["id"], "body": c["body"], "created_at": iso(c["created_at"]),
                "can_delete": c["author_id"] == ctx.uid or ctx.is_admin}
        item.update(author_fields(c, authors.get(c["author_id"]), ctx.uid))
        comments.setdefault(c["answer_id"], []).append(item)
    out = []
    for r in rows:
        like_count, liked = likes.get(r["id"], (0, False))
        item = {"id": r["id"], "question_id": r["question_id"], "body": r["body"], "like_count": like_count,
                "liked_by_me": liked, "comments": comments.get(r["id"], []), "created_at": iso(r["created_at"]),
                "can_delete": r["author_id"] == ctx.uid or ctx.is_admin}
        item.update(author_fields(r, authors.get(r["author_id"]), ctx.uid))
        out.append(item)
    return out


def _question(ctx: Ctx, question_id: Any) -> sqlite3.Row:
    row = ctx.db.execute("SELECT * FROM questions WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                         (question_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "質問が見つかりません（削除された可能性があります）")
    return row


def _answer(ctx: Ctx, answer_id: Any) -> sqlite3.Row:
    row = ctx.db.execute("SELECT * FROM answers WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                         (answer_id, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "回答が見つかりません")
    _question(ctx, row["question_id"])
    return row


def _answer_response(ctx: Ctx, answer_id: int) -> Response:
    row = ctx.db.execute("SELECT * FROM answers WHERE id = ?", (answer_id,)).fetchone()
    return Response.json({"answer": _answers_json(ctx, [row])[0]})


UNANSWERED = ("NOT EXISTS (SELECT 1 FROM answers a WHERE a.question_id = q.id AND a.deleted_at IS NULL)")


# ------------------------------------------------------------------ 森のトップ

@router.route("GET", "/api/forest")
def forest_top(ctx: Ctx) -> Response:
    cats = ctx.db.execute(
        "SELECT fc.*, (SELECT COUNT(*) FROM questions q WHERE q.category_id = fc.id AND q.deleted_at IS NULL) AS qc,"
        " (SELECT COUNT(*) FROM questions q WHERE q.category_id = fc.id AND q.deleted_at IS NULL AND " + UNANSWERED +
        ") AS uc FROM forest_categories fc WHERE fc.company_id = ? ORDER BY fc.position, fc.id", (ctx.cid,)).fetchall()
    unanswered = ctx.db.execute("SELECT * FROM questions q WHERE q.company_id = ? AND q.deleted_at IS NULL AND "
                                + UNANSWERED + " ORDER BY q.id LIMIT 10", (ctx.cid,)).fetchall()
    recent = ctx.db.execute("SELECT * FROM questions WHERE company_id = ? AND deleted_at IS NULL ORDER BY id DESC"
                            " LIMIT 20", (ctx.cid,)).fetchall()
    oldest = oldest_unanswered_by_others(ctx)
    return Response.json({
        "categories": [{"id": c["id"], "name": c["name"], "emoji": c["emoji"], "description": c["description"],
                        "question_count": c["qc"], "unanswered_count": c["uc"]} for c in cats],
        "unanswered": questions_json(ctx, unanswered),
        "recent": questions_json(ctx, recent),
        "urgency": forest_urgency(now() - oldest if oldest else None),
    })


@router.route("GET", "/api/forest/questions")
def list_questions(ctx: Ctx) -> Response:
    sql = "SELECT * FROM questions q WHERE q.company_id = ? AND q.deleted_at IS NULL"
    args: List[Any] = [ctx.cid]
    category_id = ctx.req.int_query("category_id")
    if category_id:
        sql += " AND q.category_id = ?"
        args.append(category_id)
    flt = ctx.req.query.get("filter")
    if flt == "unanswered":
        sql += " AND " + UNANSWERED
    elif flt == "mine":
        sql += " AND q.author_id = ?"
        args.append(ctx.uid)
    before = ctx.req.int_query("before")
    if before:
        sql += " AND q.id < ?"
        args.append(before)
    rows = ctx.db.execute(sql + " ORDER BY q.id DESC LIMIT 21", args).fetchall()
    rows, next_before = _page(rows, 20)
    return Response.json({"questions": questions_json(ctx, rows), "next_before": next_before})


@router.route("POST", "/api/forest/questions")
def create_question(ctx: Ctx) -> Response:
    data = ctx.req.json()
    category_id = data.get("category_id")
    if not isinstance(category_id, int) or not ctx.db.execute(
            "SELECT 1 FROM forest_categories WHERE id = ? AND company_id = ?", (category_id, ctx.cid)).fetchone():
        raise ApiError(400, "invalid_field", "カテゴリを選んでください", field="category_id")
    title = _text(ctx, "title", "タイトル", TITLE_MAX)
    body = _text(ctx, "body", "本文", BODY_MAX, required=False)
    identity, display_name = resolve_identity(ctx.db, ctx.user, ctx.company, data.get("identity"))
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO questions (company_id, category_id, author_id, title, body, identity, display_name,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, category_id, ctx.uid, title, body, identity, display_name, now()))
    question_id = int(cur.lastrowid)
    notify(ctx.db, ctx.cid, mentioned_ids(ctx, title + "\n" + body), "mention", ctx.uid, question_id=question_id,
           actor_name=display_name)
    row = ctx.db.execute("SELECT * FROM questions WHERE id = ?", (question_id,)).fetchone()
    return Response.json({"question": questions_json(ctx, [row])[0]})


@router.route("GET", "/api/forest/questions/{id:int}")
def get_question(ctx: Ctx) -> Response:
    q = _question(ctx, ctx.req.params["id"])
    ctx.db.execute("INSERT OR IGNORE INTO question_views (question_id, user_id) VALUES (?, ?)", (q["id"], ctx.uid))
    answers = ctx.db.execute("SELECT * FROM answers WHERE question_id = ? AND deleted_at IS NULL ORDER BY id",
                             (q["id"],)).fetchall()
    return Response.json({"question": questions_json(ctx, [q])[0], "answers": _answers_json(ctx, answers)})


@router.route("DELETE", "/api/forest/questions/{id:int}")
def delete_question(ctx: Ctx) -> Response:
    q = _question(ctx, ctx.req.params["id"])
    if q["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "この質問は削除できません")
    ctx.db.execute("UPDATE questions SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, q["id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="question.deleted", target_type="question",
          target_id=q["id"], detail={"by_admin": q["author_id"] != ctx.uid}, ip=ctx.req.ip)
    return Response.empty()


# ------------------------------------------------------------------ 回答・コメント

@router.route("POST", "/api/forest/questions/{id:int}/answers")
def create_answer(ctx: Ctx) -> Response:
    q = _question(ctx, ctx.req.params["id"])
    body = _text(ctx, "body", "回答", ANSWER_MAX)
    identity, display_name = resolve_identity(ctx.db, ctx.user, ctx.company, ctx.req.json().get("identity"))
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO answers (company_id, question_id, author_id, body, identity, display_name,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, q["id"], ctx.uid, body, identity, display_name, now()))
    answer_id = int(cur.lastrowid)
    mentioned = mentioned_ids(ctx, body)
    notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, question_id=q["id"], answer_id=answer_id,
           actor_name=display_name)
    if q["author_id"] not in mentioned:
        notify(ctx.db, ctx.cid, [q["author_id"]], "answer", ctx.uid, question_id=q["id"], answer_id=answer_id,
               actor_name=display_name)
    return _answer_response(ctx, answer_id)


@router.route("DELETE", "/api/forest/answers/{id:int}")
def delete_answer(ctx: Ctx) -> Response:
    a = _answer(ctx, ctx.req.params["id"])
    if a["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "この回答は削除できません")
    ctx.db.execute("UPDATE answers SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, a["id"]))
    audit(ctx.db, company_id=ctx.cid, actor_id=ctx.uid, action="answer.deleted", target_type="answer",
          target_id=a["id"], detail={"by_admin": a["author_id"] != ctx.uid}, ip=ctx.req.ip)
    return Response.empty()


@router.route("PUT", "/api/forest/answers/{id:int}/like")
def like_answer(ctx: Ctx) -> Response:
    a = _answer(ctx, ctx.req.params["id"])
    ctx.db.execute("INSERT OR IGNORE INTO answer_likes (answer_id, user_id, created_at) VALUES (?, ?, ?)",
                   (a["id"], ctx.uid, now()))
    return _answer_response(ctx, a["id"])


@router.route("DELETE", "/api/forest/answers/{id:int}/like")
def unlike_answer(ctx: Ctx) -> Response:
    a = _answer(ctx, ctx.req.params["id"])
    ctx.db.execute("DELETE FROM answer_likes WHERE answer_id = ? AND user_id = ?", (a["id"], ctx.uid))
    return _answer_response(ctx, a["id"])


@router.route("POST", "/api/forest/answers/{id:int}/comments")
def create_answer_comment(ctx: Ctx) -> Response:
    a = _answer(ctx, ctx.req.params["id"])
    body = _text(ctx, "body", "コメント", COMMENT_MAX)
    identity, display_name = resolve_identity(ctx.db, ctx.user, ctx.company, ctx.req.json().get("identity"))
    ctx.app.rate.check("post:%d" % ctx.uid, limit=30, window=60)
    cur = ctx.db.execute("INSERT INTO answer_comments (company_id, answer_id, author_id, body, identity, display_name,"
                         " created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (ctx.cid, a["id"], ctx.uid, body, identity, display_name, now()))
    mentioned = mentioned_ids(ctx, body)
    notify(ctx.db, ctx.cid, mentioned, "mention", ctx.uid, question_id=a["question_id"], answer_id=a["id"],
           actor_name=display_name)
    if a["author_id"] not in mentioned:
        notify(ctx.db, ctx.cid, [a["author_id"]], "answer_comment", ctx.uid, question_id=a["question_id"],
               answer_id=a["id"], actor_name=display_name)
    comment = [c for c in _answers_json(ctx, [a])[0]["comments"] if c["id"] == cur.lastrowid][0]
    return Response.json({"comment": comment})


@router.route("DELETE", "/api/forest/answer-comments/{id:int}")
def delete_answer_comment(ctx: Ctx) -> Response:
    row = ctx.db.execute("SELECT * FROM answer_comments WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "コメントが見つかりません")
    if row["author_id"] != ctx.uid and not ctx.is_admin:
        raise ApiError(403, "forbidden", "このコメントは削除できません")
    ctx.db.execute("UPDATE answer_comments SET deleted_at = ?, deleted_by = ? WHERE id = ?", (now(), ctx.uid, row["id"]))
    return Response.empty()


def category_admin_json(ctx: Ctx, c: sqlite3.Row) -> Dict[str, Any]:
    count = ctx.db.execute("SELECT COUNT(*) FROM questions WHERE category_id = ? AND deleted_at IS NULL",
                           (c["id"],)).fetchone()[0]
    return {"id": c["id"], "name": c["name"], "emoji": c["emoji"], "description": c["description"],
            "position": c["position"], "question_count": count}


def optional_int(value: Any) -> Optional[int]:
    return value if isinstance(value, int) and not isinstance(value, bool) else None
