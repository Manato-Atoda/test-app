"""サーバーの結合テスト（HTTP を通さず App.handle を直接呼ぶ）。

  cd tsunagu/server && python3 -m unittest -v
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import shutil
import tempfile
import unittest
from typing import Any, Dict, Optional, Tuple
from urllib.parse import parse_qs, urlparse

os.environ["TSUNAGU_PBKDF2_ITERATIONS"] = "1000"  # テストを速くする

from tsunagu_server import passwords, webauthn  # noqa: E402
from tsunagu_server.app import App  # noqa: E402
from tsunagu_server.config import Config  # noqa: E402
from tsunagu_server.db import connect  # noqa: E402
from tsunagu_server.operator_tools import DEMO_TEMP_PASSWORD, create_company, seed_demo  # noqa: E402

ORIGIN = "http://localhost:8790"


class FakeAuthenticator:
    """テスト用の疑似パスキー（ES256）。"""

    def __init__(self, rp_id: str = "localhost", origin: str = ORIGIN) -> None:
        self.rp_id, self.origin = rp_id, origin
        self.d = secrets.randbelow(webauthn.N - 1) + 1
        self.x, self.y = webauthn.p256_public_key(self.d)
        self.cred_id = secrets.token_bytes(16)
        self.count = 0
        self.user_handle: Optional[str] = None

    def _rp_hash(self) -> bytes:
        return hashlib.sha256(self.rp_id.encode()).digest()

    def create(self, public_key: Dict[str, Any]) -> Dict[str, Any]:
        self.user_handle = public_key["user"]["id"]
        cose = webauthn.cbor_encode({1: 2, 3: -7, -1: 1, -2: self.x.to_bytes(32, "big"),
                                     -3: self.y.to_bytes(32, "big")})
        client_data = json.dumps({"type": "webauthn.create", "challenge": public_key["challenge"],
                                  "origin": self.origin}).encode()
        auth_data = (self._rp_hash() + bytes([webauthn.FLAG_UP | webauthn.FLAG_UV | webauthn.FLAG_AT])
                     + self.count.to_bytes(4, "big") + bytes(16) + len(self.cred_id).to_bytes(2, "big")
                     + self.cred_id + cose)
        att = webauthn.cbor_encode({"fmt": "none", "attStmt": {}, "authData": auth_data})
        cid = webauthn.b64u_encode(self.cred_id)
        return {"id": cid, "rawId": cid, "type": "public-key",
                "response": {"clientDataJSON": webauthn.b64u_encode(client_data),
                             "attestationObject": webauthn.b64u_encode(att), "transports": ["internal"]}}

    def get(self, public_key: Dict[str, Any], *, flags: int = webauthn.FLAG_UP | webauthn.FLAG_UV,
            origin: Optional[str] = None) -> Dict[str, Any]:
        self.count += 1
        client_data = json.dumps({"type": "webauthn.get", "challenge": public_key["challenge"],
                                  "origin": origin or self.origin}).encode()
        auth_data = self._rp_hash() + bytes([flags]) + self.count.to_bytes(4, "big")
        sig = webauthn.p256_sign(self.d, auth_data + hashlib.sha256(client_data).digest(),
                                 secrets.randbelow(webauthn.N - 1) + 1)
        cid = webauthn.b64u_encode(self.cred_id)
        return {"id": cid, "rawId": cid, "type": "public-key",
                "response": {"clientDataJSON": webauthn.b64u_encode(client_data),
                             "authenticatorData": webauthn.b64u_encode(auth_data),
                             "signature": webauthn.b64u_encode(sig), "userHandle": self.user_handle}}


class ServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.cfg = Config(db_path=os.path.join(self.tmp, "t.db"), public_url=ORIGIN)
        self.app = App(self.cfg)
        db = connect(self.cfg.db_path)
        seed_demo(db, self.cfg)
        db.commit()
        db.close()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------- helpers
    def call(self, method: str, path: str, body: Any = None, token: Optional[str] = None,
             ip: str = "127.0.0.1") -> Tuple[int, Any, Dict[str, str]]:
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        raw = json.dumps(body).encode() if body is not None else b""
        resp = self.app.handle(method, path, headers, raw, ip)
        ctype = resp.headers.get("Content-Type", "")
        data: Any = resp.body
        if ctype.startswith("application/json") and resp.body:
            data = json.loads(resp.body)
        return resp.status, data, resp.headers

    def login(self, login_id: str, password: str, company: str = "DEMO") -> Tuple[int, Any]:
        status, data, _ = self.call("POST", "/api/auth/login", {
            "company_code": company, "login_id": login_id, "password": password,
            "device": {"platform": "ios", "name": "test"}})
        return status, data

    def activate(self, login_id: str, new_password: str = "NewPass-2026") -> str:
        status, data = self.login(login_id, DEMO_TEMP_PASSWORD)
        self.assertEqual(status, 200, data)
        self.assertEqual(data["status"], "password_change_required")
        status, data, _ = self.call("POST", "/api/auth/change-password",
                                    {"current_password": DEMO_TEMP_PASSWORD, "new_password": new_password},
                                    data["token"])
        self.assertEqual(status, 200, data)
        return data["token"]

    def db(self):
        return connect(self.cfg.db_path)

    # ------------------------------------------------------------- ログインと初回パスワード再設定
    def test_login_errors_are_generic(self) -> None:
        s1, d1 = self.login("E0001", "wrong-password1")
        s2, d2 = self.login("E9999", "wrong-password1")
        s3, d3 = self.login("E0001", DEMO_TEMP_PASSWORD, company="NOPE")
        self.assertEqual((s1, s2, s3), (401, 401, 401))
        self.assertEqual(d1["error"]["message"], d2["error"]["message"])
        self.assertEqual(d1["error"]["message"], d3["error"]["message"])

    def test_first_login_requires_password_change(self) -> None:
        status, data = self.login("e0002", DEMO_TEMP_PASSWORD)  # 社員コードは大文字小文字を区別しない
        self.assertEqual(data["status"], "password_change_required")
        limited = data["token"]
        status, data, _ = self.call("GET", "/api/feed", token=limited)
        self.assertEqual((status, data["error"]["code"]), (403, "password_change_required"))
        status, _, _ = self.call("GET", "/api/me", token=limited)
        self.assertEqual(status, 200)

        for bad, fragment in (("short1", "8文字以上"), ("abcdefghij", "数字"), ("12345678", "英字"),
                              ("Pass E0002x1", "半角"), ("xE0002abc9", "社員コード"),
                              (DEMO_TEMP_PASSWORD, "以前"), ("ｐａｓｓｗｏｒｄ１２", "半角")):
            status, data, _ = self.call("POST", "/api/auth/change-password",
                                        {"current_password": DEMO_TEMP_PASSWORD, "new_password": bad}, limited)
            self.assertEqual(status, 400, bad)
            self.assertTrue(any(fragment in d for d in data["error"]["details"]), (bad, data))

        status, data, _ = self.call("POST", "/api/auth/change-password",
                                    {"current_password": "wrong", "new_password": "Okay-pass-123"}, limited)
        self.assertEqual(data["error"]["code"], "invalid_current_password")

        status, data, _ = self.call("POST", "/api/auth/change-password",
                                    {"current_password": DEMO_TEMP_PASSWORD, "new_password": "kenta2026pw"}, limited)
        self.assertEqual(status, 200, data)
        self.assertFalse(data["user"]["must_change_password"])
        full = data["token"]
        self.assertEqual(self.call("GET", "/api/feed", token=full)[0], 200)
        self.assertEqual(self.call("GET", "/api/me", token=limited)[0], 401)  # 古いトークンは失効
        # 新しいパスワードでログイン → 通常のセッション（記号なし・英数字のみでも可）
        status, data = self.login("kenta.suzuki@DEMO.example", "kenta2026pw")
        self.assertEqual(data["status"], "ok")

    def test_lockout(self) -> None:
        for _ in range(5):
            self.assertEqual(self.login("E0003", "wrong-password1")[0], 401)
        status, data = self.login("E0003", DEMO_TEMP_PASSWORD)
        self.assertEqual(status, 423)
        self.assertGreater(data["error"]["retry_after_seconds"], 0)

    def test_temp_password_expiry_and_not_issued(self) -> None:
        db = self.db()
        db.execute("UPDATE users SET temp_password_expires_at = 1 WHERE employee_code = 'E0003'")
        db.commit()
        db.close()
        status, data = self.login("E0003", DEMO_TEMP_PASSWORD)
        self.assertEqual((status, data["error"]["code"]), (403, "temp_password_expired"))
        status, data = self.login("E0005", "anything123")  # 未発行
        self.assertEqual(status, 401)

    # ------------------------------------------------------------- 管理者によるアカウント発行
    def test_admin_issues_credentials_by_email_and_pdf(self) -> None:
        admin = self.activate("E0001")
        member = self.activate("E0002")
        self.assertEqual(self.call("GET", "/api/admin/users", token=member)[0], 403)

        status, data, _ = self.call("POST", "/api/admin/users", {
            "employee_code": "E0100", "display_name": "新人 一郎", "email": "Ichiro@Demo.Example",
            "department": "開発部", "role": "member"}, admin)
        self.assertEqual(status, 200, data)
        new_id = data["user"]["id"]
        self.assertEqual(data["user"]["account_state"], "not_issued")
        self.assertEqual(data["user"]["email"], "ichiro@demo.example")
        status, data, _ = self.call("POST", "/api/admin/users", {"employee_code": "e0100", "display_name": "x"}, admin)
        self.assertEqual(status, 409)

        # メールで発行 → 開発モードでは送信履歴に本文（仮パスワード入り）が残る
        status, data, _ = self.call("POST", "/api/admin/credentials", {"user_ids": [new_id], "method": "email"}, admin)
        self.assertEqual(data["sent"], [new_id], data)
        status, data, _ = self.call("GET", "/api/admin/mail", token=admin)
        body = data["messages"][0]["body"]
        self.assertIn("企業コード　　：DEMO", body)
        temp = [line.split("：", 1)[1] for line in body.splitlines() if line.startswith("仮パスワード")][0]
        self.assertRegex(temp, r"^[A-Za-z2-9]{4}-[A-Za-z2-9]{4}-[A-Za-z2-9]{4}$")
        status, data = self.login("ichiro@demo.example", temp)
        self.assertEqual(data["status"], "password_change_required")

        # PDF で再発行 → 前の仮パスワードは無効になる
        status, pdf, headers = self.call("POST", "/api/admin/credentials", {"user_ids": [new_id], "method": "pdf"}, admin)
        self.assertEqual(status, 200)
        self.assertTrue(pdf.startswith(b"%PDF-1.7"))
        self.assertEqual(headers["Content-Type"], "application/pdf")
        self.assertEqual(self.login("E0100", temp)[0], 401)

        # メールアドレスのない社員はメールで発行できない
        e4 = [u for u in self.call("GET", "/api/admin/users", token=admin)[1]["users"] if u["employee_code"] == "E0004"][0]
        status, data, _ = self.call("POST", "/api/admin/credentials", {"user_ids": [e4["id"]], "method": "email"}, admin)
        self.assertEqual(data["sent"], [])
        self.assertEqual(len(data["skipped"]), 1)

        logs = self.call("GET", "/api/admin/audit-logs", token=admin)[1]["logs"]
        self.assertTrue(any(log["action"] == "admin.credentials.issued" for log in logs))
        self.assertFalse(any(temp in json.dumps(log, ensure_ascii=False) for log in logs))

    def test_suspend_revokes_sessions(self) -> None:
        admin = self.activate("E0001")
        member = self.activate("E0003", "Yuko-pass-99")
        users = self.call("GET", "/api/admin/users", token=admin)[1]["users"]
        target = [u for u in users if u["employee_code"] == "E0003"][0]
        status, data, _ = self.call("POST", "/api/admin/users/%d/status" % target["id"], {"status": "suspended"}, admin)
        self.assertEqual(data["user"]["account_state"], "suspended")
        self.assertEqual(self.call("GET", "/api/feed", token=member)[0], 401)
        status, data = self.login("E0003", "Yuko-pass-99")
        self.assertEqual((status, data["error"]["code"]), (403, "account_suspended"))
        me = [u for u in users if u["employee_code"] == "E0001"][0]
        status, data, _ = self.call("POST", "/api/admin/users/%d/status" % me["id"], {"status": "retired"}, admin)
        self.assertEqual(status, 400)

    def test_csv_import(self) -> None:
        admin = self.activate("E0001")
        csv_text = ("社員コード,氏名,メールアドレス,部署\n"
                    "E0200,一括 花子,hanako@demo.example,経理部\n"
                    "E0001,重複 太郎,,\n"
                    "bad code!,不正 コード,,\n")
        status, data, _ = self.call("POST", "/api/admin/users/import", {"csv": csv_text}, admin)
        self.assertEqual(data["created"], 1, data)
        self.assertEqual([e["line"] for e in data["errors"]], [3, 4])

    def test_settings_require_symbol(self) -> None:
        admin = self.activate("E0001")
        status, data, _ = self.call("PATCH", "/api/admin/settings",
                                    {"password_require_symbol": True, "password_min_length": 10}, admin)
        self.assertTrue(data["password_policy"]["require_symbol"])
        status, data = self.login("E0002", DEMO_TEMP_PASSWORD)
        limited = data["token"]
        status, data, _ = self.call("POST", "/api/auth/change-password",
                                    {"current_password": DEMO_TEMP_PASSWORD, "new_password": "abcdefgh123"}, limited)
        self.assertTrue(any("記号" in d for d in data["error"]["details"]))
        status, data, _ = self.call("POST", "/api/auth/change-password",
                                    {"current_password": DEMO_TEMP_PASSWORD, "new_password": "abc-defg-123"}, limited)
        self.assertEqual(status, 200, data)

    # ------------------------------------------------------------- SNS
    def test_posts_comments_reactions_ack_and_notifications(self) -> None:
        admin = self.activate("E0001")
        kenta = self.activate("E0002")
        sho = self.activate("E0004", "Sho-design-7")
        channels = {c["name"]: c for c in self.call("GET", "/api/channels", token=kenta)[1]["channels"]}
        self.assertNotIn("経営企画", channels)  # 非公開チャンネルは見えない
        self.assertFalse(channels["お知らせ"]["can_post"])
        status, data, _ = self.call("POST", "/api/posts", {"channel_id": channels["お知らせ"]["id"], "body": "x"}, kenta)
        self.assertEqual(status, 403)
        status, data, _ = self.call("POST", "/api/posts", {"channel_id": channels["全社"]["id"], "body": "x",
                                                           "kind": "announcement"}, kenta)
        self.assertEqual(status, 403)

        status, data, _ = self.call("POST", "/api/posts", {
            "channel_id": channels["開発部"]["id"], "body": "@E0004 レビューお願いします。mail: a@E0001.jp"}, kenta)
        self.assertEqual(status, 200, data)
        post_id = data["post"]["id"]
        notes = self.call("GET", "/api/notifications", token=sho)[1]
        self.assertTrue(any(n["type"] == "mention" and n["post_id"] == post_id for n in notes["notifications"]))
        admin_notes = self.call("GET", "/api/notifications", token=admin)[1]["notifications"]
        self.assertFalse(any(n["post_id"] == post_id for n in admin_notes))  # メールアドレスはメンション扱いしない

        status, data, _ = self.call("POST", "/api/posts/%d/comments" % post_id, {"body": "見ます！"}, sho)
        self.assertEqual(status, 200)
        status, data, _ = self.call("PUT", "/api/posts/%d/like" % post_id, token=sho)
        self.assertEqual((data["post"]["like_count"], data["post"]["liked_by_me"]), (1, True))
        self.assertEqual(data["post"]["comment_count"], 1)
        self.assertNotIn("reactions", data["post"])
        kenta_notes = self.call("GET", "/api/notifications", token=kenta)[1]
        self.assertEqual(kenta_notes["notifications"][0]["type"], "comment")

        status, data, _ = self.call("PATCH", "/api/posts/%d" % post_id, {"body": "編集しました"}, sho)
        self.assertEqual(status, 403)
        status, data, _ = self.call("PATCH", "/api/posts/%d" % post_id, {"body": "編集しました"}, kenta)
        self.assertIsNotNone(data["post"]["edited_at"])

        # お知らせ（確認ボタン付き）
        status, data, _ = self.call("POST", "/api/posts", {"channel_id": channels["お知らせ"]["id"],
                                                           "body": "健康診断のお知らせ", "kind": "announcement",
                                                           "require_ack": True}, admin)
        ann = data["post"]["id"]
        self.assertTrue(any(n["type"] == "announcement" for n in
                            self.call("GET", "/api/notifications", token=kenta)[1]["notifications"]))
        data = self.call("POST", "/api/posts/%d/ack" % ann, token=kenta)[1]
        self.assertTrue(data["post"]["acked_by_me"])
        self.assertEqual(self.call("GET", "/api/posts/%d/acks" % ann, token=kenta)[0], 403)
        acks = self.call("GET", "/api/posts/%d/acks" % ann, token=admin)[1]
        self.assertEqual([u["employee_code"] for u in acks["acked"]], ["E0002"])
        self.assertIn("E0005", [u["employee_code"] for u in acks["not_acked"]])
        feed = self.call("GET", "/api/feed?kind=announcement", token=kenta)[1]
        self.assertTrue(all(p["kind"] == "announcement" for p in feed["posts"]))

        # 通報 → 管理者が非表示 → 一覧から消える
        rid = self.call("POST", "/api/reports", {"target_type": "post", "target_id": post_id, "reason": "テスト"},
                        sho)[1]["report_id"]
        reports = self.call("GET", "/api/admin/reports", token=admin)[1]["reports"]
        self.assertEqual(reports[0]["id"], rid)
        self.call("POST", "/api/admin/reports/%d/resolve" % rid, {"action": "hide"}, admin)
        self.assertEqual(self.call("GET", "/api/posts/%d" % post_id, token=kenta)[0], 404)

        # 社員名簿・検索
        users = self.call("GET", "/api/directory?q=開発", token=kenta)[1]["users"]
        self.assertEqual(sorted(u["employee_code"] for u in users), ["E0002", "E0004"])
        found = self.call("GET", "/api/search?q=健康診断", token=kenta)[1]["posts"]
        self.assertEqual([p["id"] for p in found], [ann])
        self.assertEqual(self.call("GET", "/api/search?q=来期", token=kenta)[1]["posts"], [])  # 非公開

    def test_pagination(self) -> None:
        token = self.activate("E0002")
        channel = [c for c in self.call("GET", "/api/channels", token=token)[1]["channels"] if c["name"] == "雑談"][0]
        for i in range(25):
            self.call("POST", "/api/posts", {"channel_id": channel["id"], "body": "投稿 %d" % i}, token)
        page1 = self.call("GET", "/api/feed?channel_id=%d&limit=10" % channel["id"], token=token)[1]
        page2 = self.call("GET", "/api/feed?channel_id=%d&limit=10&before=%d" % (channel["id"], page1["next_before"]),
                          token=token)[1]
        self.assertEqual(len(page1["posts"]), 10)
        self.assertLess(page2["posts"][0]["id"], page1["posts"][-1]["id"])

    def test_tenant_isolation(self) -> None:
        demo = self.activate("E0001")
        db = self.db()
        _, _, notice = create_company(db, self.cfg, code="acme", name="エーシーエムイー株式会社",
                                      admin={"employee_code": "E0001", "display_name": "別会社 太郎"})
        db.commit()
        db.close()
        status, data = self.login("E0001", notice.temporary_password, company="ACME")
        self.assertEqual(data["company"]["code"], "ACME")
        limited = data["token"]
        other = self.call("POST", "/api/auth/change-password",
                          {"current_password": notice.temporary_password, "new_password": "Acme-admin-1"},
                          limited)[1]["token"]
        demo_post = self.call("GET", "/api/feed", token=demo)[1]["posts"][0]["id"]
        self.assertEqual(self.call("GET", "/api/posts/%d" % demo_post, token=other)[0], 404)
        self.assertEqual([u["employee_code"] for u in self.call("GET", "/api/directory", token=other)[1]["users"]],
                         ["E0001"])
        self.assertEqual(self.call("GET", "/api/admin/users", token=other)[1]["users"][0]["display_name"], "別会社 太郎")
        demo_user = self.call("GET", "/api/directory", token=demo)[1]["users"][0]["id"]
        self.assertEqual(self.call("POST", "/api/admin/users/%d/status" % demo_user, {"status": "suspended"},
                                   other)[0], 404)

    # ------------------------------------------------------------- パスキー
    def test_passkey_register_and_app_login(self) -> None:
        token = self.activate("E0002")
        ticket = self.call("POST", "/api/me/passkeys/ticket", token=token)[1]
        self.assertIn("/passkey/register?ticket=", ticket["register_url"])
        options = self.call("POST", "/api/passkeys/register/options", {"ticket": ticket["ticket"]})[1]
        self.assertEqual(options["publicKey"]["rp"]["id"], "localhost")
        self.assertEqual(options["publicKey"]["user"]["name"], "DEMO/E0002")
        # チケットは 1 回限り
        self.assertEqual(self.call("POST", "/api/passkeys/register/options", {"ticket": ticket["ticket"]})[0], 400)

        authenticator = FakeAuthenticator()
        status, data, _ = self.call("POST", "/api/passkeys/register/verify", {
            "challenge_id": options["challenge_id"], "name": "テスト端末",
            "credential": authenticator.create(options["publicKey"])})
        self.assertEqual(status, 200, data)
        self.assertEqual(self.call("GET", "/api/me", token=token)[1]["user"]["passkey_count"], 1)

        # アプリからのログイン（PKCE）
        verifier = secrets.token_urlsafe(48)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        opts = self.call("POST", "/api/auth/passkey/options", {"company_code": "demo", "login_id": "E0002"})[1]
        self.assertEqual(opts["publicKey"]["allowCredentials"], [])
        status, data, _ = self.call("POST", "/api/auth/passkey/verify", {
            "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"]),
            "app_redirect": {"redirect_uri": "tsunagu://auth", "code_challenge": challenge, "state": "s1"}})
        self.assertEqual(data["status"], "redirect", data)
        query = parse_qs(urlparse(data["redirect_url"]).query)
        self.assertEqual(query["state"], ["s1"])
        code = query["code"][0]
        bad = self.call("POST", "/api/auth/exchange", {"code": code, "code_verifier": "x" * 43})
        self.assertEqual(bad[0], 400)
        # 間違った verifier を試すとそのコードは使えなくなる
        self.assertEqual(self.call("POST", "/api/auth/exchange", {"code": code, "code_verifier": verifier})[0], 400)

        opts = self.call("POST", "/api/auth/passkey/options", {"company_code": "DEMO"})[1]
        data = self.call("POST", "/api/auth/passkey/verify", {
            "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"]),
            "app_redirect": {"redirect_uri": "tsunagu://auth", "code_challenge": challenge, "state": "s2"}})[1]
        code = parse_qs(urlparse(data["redirect_url"]).query)["code"][0]
        status, data, _ = self.call("POST", "/api/auth/exchange", {
            "code": code, "code_verifier": verifier, "device": {"platform": "android", "name": "Pixel"}})
        self.assertEqual((status, data["status"]), (200, "ok"), data)
        self.assertEqual(data["user"]["employee_code"], "E0002")
        self.assertEqual(self.call("GET", "/api/feed", token=data["token"])[0], 200)
        self.assertEqual(self.call("POST", "/api/auth/exchange", {"code": code, "code_verifier": verifier})[0], 400)

        # ブラウザ（管理コンソール等）からの直接ログイン
        opts = self.call("POST", "/api/auth/passkey/options", {"company_code": "DEMO"})[1]
        data = self.call("POST", "/api/auth/passkey/verify", {
            "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"])})[1]
        self.assertEqual(data["status"], "ok")

    def test_passkey_rejections(self) -> None:
        token = self.activate("E0002")
        ticket = self.call("POST", "/api/me/passkeys/ticket", token=token)[1]["ticket"]
        options = self.call("POST", "/api/passkeys/register/options", {"ticket": ticket})[1]
        authenticator = FakeAuthenticator()
        self.call("POST", "/api/passkeys/register/verify", {
            "challenge_id": options["challenge_id"], "credential": authenticator.create(options["publicKey"])})

        def attempt(company: str = "DEMO", **kwargs: Any) -> int:
            opts = self.call("POST", "/api/auth/passkey/options", {"company_code": company})[1]
            return self.call("POST", "/api/auth/passkey/verify", {
                "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"], **kwargs)})[0]

        self.assertEqual(attempt(origin="https://evil.example"), 401)
        self.assertEqual(attempt(flags=webauthn.FLAG_UP), 401)  # 本人確認（UV）なし
        self.assertEqual(attempt(company="NOPE"), 401)
        self.assertEqual(attempt(), 200)
        # 署名カウンタが戻ったら拒否
        authenticator.count = 0
        self.assertEqual(attempt(), 401)
        # 不正な戻り先
        authenticator.count = 100
        opts = self.call("POST", "/api/auth/passkey/options", {"company_code": "DEMO"})[1]
        status, data, _ = self.call("POST", "/api/auth/passkey/verify", {
            "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"]),
            "app_redirect": {"redirect_uri": "https://evil.example/cb", "code_challenge": "a" * 43}})
        self.assertEqual(data["error"]["code"], "invalid_redirect")
        # チャレンジの再利用は不可
        status, data, _ = self.call("POST", "/api/auth/passkey/verify", {
            "challenge_id": opts["challenge_id"], "credential": authenticator.get(opts["publicKey"])})
        self.assertEqual(status, 400)


class UnitTest(unittest.TestCase):
    def test_temporary_password_meets_policy(self) -> None:
        policy = passwords.policy_from_settings({"password_require_symbol": True})
        for _ in range(50):
            temp = passwords.generate_temporary_password()
            self.assertEqual(passwords.check_policy(temp, policy), [], temp)
            self.assertFalse(set(temp) & set("0O1lI"))

    def test_pdf_contains_japanese_font_and_pages(self) -> None:
        from tsunagu_server.pdf import AccountNotice, build_account_notices_pdf
        notice = AccountNotice("デモ株式会社", "DEMO", "佐藤 美咲", "総務部", "E0001", None, "Abcd-Efgh-2345",
                               "2026年11月23日(月) 10:00", "2026年11月20日(金)", ORIGIN)
        pdf = build_account_notices_pdf([notice, notice])
        self.assertIn(b"/HeiseiKakuGo-W5", pdf)
        self.assertIn(b"/Count 2", pdf)
        self.assertTrue(pdf.rstrip().endswith(b"%%EOF"))


if __name__ == "__main__":
    unittest.main()
