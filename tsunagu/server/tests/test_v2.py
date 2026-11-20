"""v2（M：Galaxia 寄せ）の機能のテスト。

  cd tsunagu/server && python3 -m unittest -v
"""
from __future__ import annotations

import os
import struct
import zlib
from unittest import mock

from tests.test_server import ServerTest  # 共通の準備（デモ企業・call・activate）

from tsunagu_server.db import connect, migrate  # noqa: E402
from tsunagu_server.operator_tools import create_company  # noqa: E402


def tiny_png(width: int = 3, height: int = 2) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class V2Test(ServerTest):
    def upload(self, token: str, data: bytes, ctype: str = "image/png"):
        headers = {"Content-Type": ctype, "Authorization": "Bearer " + token}
        resp = self.app.handle("POST", "/api/uploads", headers, data, "127.0.0.1")
        import json
        return resp.status, (json.loads(resp.body) if resp.body else None)

    def channel(self, token: str, name: str) -> dict:
        return [c for c in self.call("GET", "/api/channels", token=token)[1]["channels"] if c["name"] == name][0]

    # ------------------------------------------------------------- いいね・保存・シェア・引用・閲覧
    def test_like_bookmark_share_quote_views(self) -> None:
        kenta = self.activate("E0002")
        yuko = self.activate("E0003", "Yuko-pass-99")
        zensha = self.channel(kenta, "全社")
        self.assertEqual(zensha["emoji"], "🏢")
        post = self.call("POST", "/api/posts", {"channel_id": zensha["id"], "body": "元の投稿"}, kenta)[1]["post"]
        pid = post["id"]

        # いいね: 件数と自分の有無だけ（誰が押したかは返さない）
        data = self.call("PUT", "/api/posts/%d/like" % pid, token=yuko)[1]["post"]
        self.assertEqual((data["like_count"], data["liked_by_me"]), (1, True))
        data = self.call("GET", "/api/posts/%d" % pid, token=kenta)[1]["post"]
        self.assertEqual((data["like_count"], data["liked_by_me"]), (1, False))
        self.call("DELETE", "/api/posts/%d/like" % pid, token=yuko)

        # 保存
        self.assertTrue(self.call("PUT", "/api/posts/%d/bookmark" % pid, token=yuko)[1]["post"]["bookmarked_by_me"])
        marks = self.call("GET", "/api/bookmarks", token=yuko)[1]["posts"]
        self.assertEqual([p["id"] for p in marks], [pid])

        # そのままシェア → 元の投稿に通知、もう一度押しても 1 回だけ
        share = self.call("POST", "/api/posts/%d/share" % pid, token=yuko)[1]["post"]
        self.assertEqual((share["kind"], share["quote_of"]["id"], share["body"]), ("share", pid, ""))
        again = self.call("POST", "/api/posts/%d/share" % pid, token=yuko)[1]["post"]
        self.assertEqual(again["id"], share["id"])
        original = self.call("GET", "/api/posts/%d" % pid, token=yuko)[1]["post"]
        self.assertEqual((original["share_count"], original["shared_by_me"]), (1, True))
        # シェアに対するいいねは元の投稿に付く
        self.assertEqual(self.call("PUT", "/api/posts/%d/like" % share["id"], token=kenta)[1]["post"]["id"], pid)
        types = [n["type"] for n in self.call("GET", "/api/notifications", token=kenta)[1]["notifications"]]
        self.assertIn("share", types)
        undone = self.call("DELETE", "/api/posts/%d/share" % pid, token=yuko)[1]["post"]
        self.assertEqual((undone["share_count"], undone["shared_by_me"]), (0, False))

        # 引用（元と同じチャンネルに入る）
        quote = self.call("POST", "/api/posts", {"quote_of": pid, "body": "引用します", "channel_id": 999}, yuko)[1]["post"]
        self.assertEqual((quote["channel"]["id"], quote["quote_of"]["id"]), (zensha["id"], pid))
        self.assertIn("quote", [n["type"] for n in self.call("GET", "/api/notifications", token=kenta)[1]["notifications"]])

        # お知らせ（管理者のみ投稿のチャンネル）はシェアできない
        notice = self.call("GET", "/api/feed?kind=announcement", token=yuko)[1]["posts"][0]
        self.assertEqual(self.call("POST", "/api/posts/%d/share" % notice["id"], token=yuko)[0], 403)

        # 閲覧数（同じ人は 1 回）
        self.call("POST", "/api/posts/views", {"ids": [pid, pid]}, yuko)
        self.call("POST", "/api/posts/views", {"ids": [pid]}, yuko)
        self.assertEqual(self.call("GET", "/api/posts/%d" % pid, token=kenta)[1]["post"]["view_count"], 1)

        # 新しい投稿の確認（after）
        newer = self.call("GET", "/api/feed?after=%d" % pid, token=kenta)[1]["posts"]
        self.assertEqual([p["id"] for p in newer], [quote["id"]])

    def test_comments_quick_like_edit_and_drafts(self) -> None:
        kenta = self.activate("E0002")
        sho = self.activate("E0004", "Sho-design-7")
        pid = self.call("GET", "/api/feed", token=kenta)[1]["posts"][0]["id"]
        c = self.call("POST", "/api/posts/%d/comments" % pid, {"quick_index": 0}, sho)[1]["comment"]
        self.assertEqual((c["body"], c["is_quick"]), ("👏 ナイス！", True))
        liked = self.call("PUT", "/api/comments/%d/like" % c["id"], token=kenta)[1]["comment"]
        self.assertEqual((liked["like_count"], liked["liked_by_me"]), (1, True))
        self.assertEqual(self.call("PATCH", "/api/comments/%d" % c["id"], {"body": "x"}, kenta)[0], 403)
        edited = self.call("PATCH", "/api/comments/%d" % c["id"], {"body": "書き直しました"}, sho)[1]["comment"]
        self.assertEqual((edited["body"], edited["is_quick"]), ("書き直しました", False))
        self.assertIsNotNone(edited["edited_at"])

        draft = self.call("POST", "/api/drafts", {"body": "あとで書く", "identity": "anonymous"}, kenta)[1]["draft"]
        self.assertEqual(len(self.call("GET", "/api/drafts", token=kenta)[1]["drafts"]), 1)
        channel = self.channel(kenta, "雑談")
        self.call("POST", "/api/posts", {"channel_id": channel["id"], "body": "書けた", "draft_id": draft["id"]}, kenta)
        self.assertEqual(self.call("GET", "/api/drafts", token=kenta)[1]["drafts"], [])

    # ------------------------------------------------------------- 発信者（実名・部署名・匿名）
    def test_identity_hides_author(self) -> None:
        kenta = self.activate("E0002")
        admin = self.activate("E0001")
        channel = self.channel(kenta, "雑談")
        post = self.call("POST", "/api/posts", {"channel_id": channel["id"], "body": "匿名で相談です",
                                                "identity": "anonymous"}, kenta)[1]["post"]
        self.assertEqual((post["author"], post["display_name"], post["is_mine"]), (None, "ぽんず", True))
        seen_by_admin = self.call("GET", "/api/posts/%d" % post["id"], token=admin)[1]["post"]
        self.assertIsNone(seen_by_admin["author"])
        self.assertFalse(seen_by_admin["is_mine"])
        dept = self.call("POST", "/api/posts/%d/comments" % post["id"], {"body": "わかります",
                                                                        "identity": "department"}, admin)[1]["comment"]
        self.assertEqual((dept["author"], dept["display_name"]), (None, "総務部"))
        # コメント通知は、実名を出さない
        note = self.call("GET", "/api/notifications", token=kenta)[1]["notifications"][0]
        self.assertEqual((note["actor"], note["actor_name"]), (None, "総務部"))
        # プロフィールには実名の投稿だけ
        me = self.call("GET", "/api/me", token=kenta)[1]["user"]
        profile = self.call("GET", "/api/users/%d" % me["id"], token=admin)[1]
        self.assertNotIn(post["id"], [p["id"] for p in profile["posts"]])
        # あだ名が未登録なら匿名では発信できない（E0001 は未登録）
        status, data, _ = self.call("POST", "/api/posts", {"channel_id": channel["id"], "body": "x",
                                                           "identity": "anonymous"}, admin)
        self.assertEqual((status, data["error"]["code"]), (400, "identity_unavailable"))
        # 管理者が匿名を無効にすると使えない
        self.call("PATCH", "/api/admin/settings", {"identity_anonymous_enabled": False}, admin)
        status, _, _ = self.call("POST", "/api/posts", {"channel_id": channel["id"], "body": "x",
                                                        "identity": "anonymous"}, kenta)
        self.assertEqual(status, 400)
        features = self.call("GET", "/api/me", token=kenta)[1]["company"]["features"]
        self.assertEqual(features, {"identity_department": True, "identity_anonymous": False, "watermark": False})
        # 通報の対応画面では、管理者は本人がわかる
        self.call("POST", "/api/reports", {"target_type": "post", "target_id": post["id"], "reason": "確認"}, admin)
        report = self.call("GET", "/api/admin/reports", token=admin)[1]["reports"][0]
        self.assertEqual((report["author"]["employee_code"], report["author_identity"]), ("E0002", "anonymous"))

    def test_profile_nickname_and_images(self) -> None:
        kenta = self.activate("E0002")
        status, img = self.upload(kenta, tiny_png(30, 20))
        self.assertEqual((status, img["width"], img["height"]), (200, 30, 20))
        me = self.call("PATCH", "/api/me", {"nickname": "らっこ", "avatar_upload_id": img["id"],
                                            "bio": "よろしく"}, kenta)[1]["user"]
        self.assertEqual((me["nickname"], me["avatar_url"]), ("らっこ", "/api/uploads/" + img["id"]))
        self.assertEqual(self.call("PATCH", "/api/me", {"nickname": "鈴木 健太"}, kenta)[0], 400)
        # 画像は同じ企業のログイン中の人だけ
        resp = self.app.handle("GET", "/api/uploads/" + img["id"], {"Authorization": "Bearer " + kenta}, b"", "x")
        self.assertEqual((resp.status, resp.headers["Content-Type"]), (200, "image/png"))
        self.assertEqual(self.app.handle("GET", "/api/uploads/" + img["id"], {}, b"", "x").status, 401)
        # 画像以外・壊れたファイルは受け付けない
        self.assertEqual(self.upload(kenta, b"<?php echo 1; ?>", "image/png")[0], 415)
        # 投稿に画像を付ける（他人の画像は使えない）
        sho = self.activate("E0004", "Sho-design-7")
        channel = self.channel(kenta, "雑談")
        post = self.call("POST", "/api/posts", {"channel_id": channel["id"], "image_ids": [img["id"]]}, kenta)[1]["post"]
        self.assertEqual(post["images"][0]["id"], img["id"])
        self.assertEqual(self.call("POST", "/api/posts", {"channel_id": channel["id"], "image_ids": [img["id"]]},
                                   sho)[0], 400)

    # ------------------------------------------------------------- COMMIT・森・バッジ・右側の欄
    def test_commits_badges_and_highlights(self) -> None:
        kenta = self.activate("E0002")
        yuko = self.activate("E0003", "Yuko-pass-99")
        commits = self.call("GET", "/api/commits", token=kenta)[1]["posts"]
        self.assertEqual(len(commits), 2)
        self.assertIsNone(commits[0]["channel"])
        badges = self.call("GET", "/api/badges", token=kenta)[1]
        self.assertTrue(badges["commit_has_new"])
        self.assertEqual(badges["announcements_unacked"], 0)  # E0002 は確認済み
        self.call("POST", "/api/seen/commit", token=kenta)
        self.assertFalse(self.call("GET", "/api/badges", token=kenta)[1]["commit_has_new"])
        made = self.call("POST", "/api/commits", {"body": "明日までに見積もりを出します"}, yuko)[1]["post"]
        self.assertEqual(made["kind"], "commit")
        self.assertTrue(self.call("GET", "/api/badges", token=kenta)[1]["commit_has_new"])
        mine = self.call("GET", "/api/commits?user_id=%d&period=week" % made["author"]["id"], token=kenta)[1]["posts"]
        self.assertEqual(mine[0]["id"], made["id"])
        self.assertTrue(all(p["author"]["employee_code"] == "E0003" for p in mine))
        # COMMIT はホームに出ない・チャンネル一覧にも出ない
        self.assertNotIn(made["id"], [p["id"] for p in self.call("GET", "/api/feed", token=kenta)[1]["posts"]])
        self.assertNotIn("__commit__", [c["name"] for c in self.call("GET", "/api/channels", token=kenta)[1]["channels"]])
        self.assertEqual(self.call("POST", "/api/seen/evil", token=kenta)[0], 400)

        highlights = self.call("GET", "/api/highlights", token=yuko)[1]
        self.assertIn("E0003", [u["employee_code"] for u in highlights["members_today"]])
        self.assertTrue(highlights["trending"])
        likes = [r for r in highlights["recent_reactions"] if r["type"] == "like"]
        self.assertTrue(likes and all(r["actor"] is None for r in likes))

    def test_forest(self) -> None:
        kenta = self.activate("E0002")
        yuko = self.activate("E0003", "Yuko-pass-99")
        top = self.call("GET", "/api/forest", token=kenta)[1]
        self.assertEqual(top["categories"][0]["name"], "みんなの広場")
        self.assertEqual(len(top["unanswered"]), 1)
        self.assertEqual(top["urgency"], "warm")  # 30 時間前の未回答の質問
        self.assertTrue(self.call("GET", "/api/badges", token=kenta)[1]["forest_has_new"])
        question = top["unanswered"][0]
        self.assertEqual((question["author"], question["display_name"]), (None, "みかん"))
        answer = self.call("POST", "/api/forest/questions/%d/answers" % question["id"],
                           {"body": "毎月 25 日です"}, kenta)[1]["answer"]
        note = self.call("GET", "/api/notifications", token=yuko)[1]["notifications"][0]
        self.assertEqual((note["type"], note["target"]), ("answer", {"type": "question", "id": question["id"]}))
        liked = self.call("PUT", "/api/forest/answers/%d/like" % answer["id"], token=yuko)[1]["answer"]
        self.assertEqual(liked["like_count"], 1)
        comment = self.call("POST", "/api/forest/answers/%d/comments" % answer["id"],
                            {"body": "助かります！", "identity": "anonymous"}, yuko)[1]["comment"]
        self.assertEqual(comment["display_name"], "みかん")
        detail = self.call("GET", "/api/forest/questions/%d" % question["id"], token=kenta)[1]
        self.assertEqual((detail["question"]["answer_count"], detail["question"]["view_count"]), (1, 1))
        self.assertEqual(len(detail["answers"][0]["comments"]), 1)
        self.assertEqual(self.call("GET", "/api/forest", token=kenta)[1]["urgency"], "calm")
        cat = top["categories"][0]["id"]
        made = self.call("POST", "/api/forest/questions", {"category_id": cat, "title": "おすすめのランチは？",
                                                           "body": ""}, kenta)[1]["question"]
        mine = self.call("GET", "/api/forest/questions?filter=mine", token=kenta)[1]["questions"]
        self.assertEqual([q["id"] for q in mine], [made["id"]])
        self.assertEqual(self.call("DELETE", "/api/forest/questions/%d" % made["id"], token=yuko)[0], 403)
        self.assertEqual(self.call("DELETE", "/api/forest/questions/%d" % made["id"], token=kenta)[0], 204)

    # ------------------------------------------------------------- 管理
    def test_admin_insights_and_categories(self) -> None:
        admin = self.activate("E0001")
        data = self.call("GET", "/api/admin/insights", token=admin)[1]
        self.assertFalse(data["ai"]["configured"])
        self.assertEqual(len(data["stats"]["daily"]), 30)
        self.assertEqual(data["stats"]["totals"]["commits_30d"], 2)
        status, err, _ = self.call("POST", "/api/admin/insights/generate", token=admin)
        self.assertEqual((status, err["error"]["code"]), (400, "ai_not_configured"))
        with mock.patch.dict(os.environ, {"TSUNAGU_AI_PROVIDER": "mock"}):
            report = self.call("POST", "/api/admin/insights/generate", token=admin)[1]["report"]
        self.assertIn("仮レポート", report["content"])
        self.assertNotIn("E0004", report["content"])  # 社員コードは送らない
        cat = self.call("POST", "/api/admin/forest-categories", {"name": "総務", "emoji": "🗂️"}, admin)[1]["category"]
        self.assertEqual(cat["emoji"], "🗂️")
        channel = self.call("POST", "/api/admin/channels", {"name": "広報", "emoji": "📣"}, admin)[1]["channel"]
        self.assertEqual(channel["emoji"], "📣")
        self.assertNotIn("__commit__", [c["name"] for c in self.call("GET", "/api/admin/channels", token=admin)[1]["channels"]])
        self.call("PATCH", "/api/admin/settings", {"watermark_mobile": True}, admin)
        self.assertTrue(self.call("GET", "/api/me", token=admin)[1]["company"]["features"]["watermark"])

    def test_tenant_isolation_v2(self) -> None:
        kenta = self.activate("E0002")
        status, img = self.upload(kenta, tiny_png())
        db = connect(self.cfg.db_path)
        _, _, notice = create_company(db, self.cfg, code="OTHER", name="他社", admin={
            "employee_code": "A1", "display_name": "他社 太郎"})
        db.commit()
        db.close()
        limited = self.login("A1", notice.temporary_password, company="OTHER")[1]["token"]
        other = self.call("POST", "/api/auth/change-password", {"current_password": notice.temporary_password,
                                                                "new_password": "Other-pass-1"}, limited)[1]["token"]
        resp = self.app.handle("GET", "/api/uploads/" + img["id"], {"Authorization": "Bearer " + other}, b"", "x")
        self.assertEqual(resp.status, 404)
        self.assertEqual(self.call("GET", "/api/commits", token=other)[1]["posts"], [])
        self.assertEqual(self.call("GET", "/api/forest", token=other)[1]["recent"], [])
        demo_q = self.call("GET", "/api/forest", token=kenta)[1]["recent"][0]["id"]
        self.assertEqual(self.call("GET", "/api/forest/questions/%d" % demo_q, token=other)[0], 404)

    # ------------------------------------------------------------- 古いデータベースからの移行
    def test_migration_from_v1(self) -> None:
        db = connect(self.cfg.db_path)
        post_id = db.execute("SELECT id FROM posts LIMIT 1").fetchone()[0]
        user_id = db.execute("SELECT id FROM users WHERE employee_code = 'E0005'").fetchone()[0]
        db.execute("INSERT INTO reactions (post_id, user_id, reaction, created_at) VALUES (?, ?, 'clap', 1)",
                   (post_id, user_id))
        db.execute("INSERT INTO reactions (post_id, user_id, reaction, created_at) VALUES (?, ?, 'idea', 2)",
                   (post_id, user_id))
        db.execute("ALTER TABLE users DROP COLUMN nickname")
        db.commit()
        migrate(db)
        db.commit()
        self.assertIn("nickname", [r[1] for r in db.execute("PRAGMA table_info(users)")])
        self.assertEqual(db.execute("SELECT COUNT(*) FROM likes WHERE post_id = ? AND user_id = ?",
                                    (post_id, user_id)).fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM reactions").fetchone()[0], 0)
        db.close()


# ServerTest のテストを二重に実行しないよう、このモジュールでは V2Test 独自のものだけを残す
for _name in [n for n in dir(ServerTest) if n.startswith("test_")]:
    if _name not in V2Test.__dict__:
        setattr(V2Test, _name, None)
del ServerTest
