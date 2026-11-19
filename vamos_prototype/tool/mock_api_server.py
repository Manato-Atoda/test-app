#!/usr/bin/env python3
"""VAMOS 試作アプリ用のモック API サーバー（標準ライブラリのみ）。

本番のサーバー（XServer 上の PHP）を想定し、アプリが使う API の形を確かめるためのもの。
データは tool/import_vamos_data.py が書き出した assets/vamos/ を読み込む。
状態（会員・端末）はメモリ上だけに持ち、再起動で消える。

    python3 -I tool/mock_api_server.py --port 8787

主な API（JSON）:
    GET  /api/v1/health
    GET  /api/v1/interviews            一覧（本文なし）
    GET  /api/v1/interviews/{slug}     詳細（本文ブロックあり）
    GET  /api/v1/topics                一覧（本文あり）
    POST /api/v1/auth/code             {email} → 確認コードを発行（試作のため応答にも含める）
    POST /api/v1/auth/verify           {email, code} → {token, user}
    GET  /api/v1/me / PUT /api/v1/me   会員情報（Bearer トークン）
    POST /api/v1/auth/logout
    POST /api/v1/devices               {platform, token} → 通知先として登録
    POST /api/v1/admin/push            {slug} → 登録端末へ通知（iOS シミュレーターは simctl で配信）
    GET  /admin                        通知配信の管理画面（ブラウザ用）
"""

from __future__ import annotations

import argparse
import html as htmllib
import json
import mimetypes
import re
import secrets
import subprocess
import tempfile
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

APP_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = APP_ROOT / "assets" / "vamos"
BUNDLE_ID = "io.github.manatoatoda.vamosPrototype"
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class State:
    """会員・確認コード・通知先の端末（メモリ上）。"""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.codes: dict[str, str] = {}
        self.tokens: dict[str, str] = {}  # token -> email
        self.users: dict[str, dict] = {}  # email -> user
        self.devices: dict[str, dict] = {}  # device token -> device
        self.push_log: list[dict] = []


STATE = State()


def now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def load_content() -> tuple[list[dict], list[dict]]:
    interviews = json.loads((DATA_DIR / "data" / "interviews.json").read_text(encoding="utf-8"))
    topics = json.loads((DATA_DIR / "data" / "topics.json").read_text(encoding="utf-8"))
    return interviews, topics


INTERVIEWS, TOPICS = load_content()


def media_url(base: str, path: str | None) -> str | None:
    """assets/vamos/images/... → http://host/media/..."""
    if not path:
        return path
    return base + "/media/" + path.split("assets/vamos/images/", 1)[-1]


def with_media(base: str, item: dict) -> dict:
    item = json.loads(json.dumps(item))
    if "thumbnail" in item:
        item["thumbnail"] = media_url(base, item["thumbnail"])
    for block in item.get("blocks", []):
        for key in ("src", "avatar"):
            if block.get(key):
                block[key] = media_url(base, block[key])
    return item


def public_user(user: dict) -> dict:
    return {k: v for k, v in user.items() if k != "createdAt"}


class Handler(BaseHTTPRequestHandler):
    server_version = "VamosMockAPI/0.1"

    # -- helpers ----------------------------------------------------------
    @property
    def base(self) -> str:
        return "http://" + (self.headers.get("Host") or "localhost")

    def send_json(self, data, status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def error(self, status: int, message: str) -> None:
        self.send_json({"error": message}, status)

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 64 * 1024:
            return {}
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    def current_user(self) -> dict | None:
        header = self.headers.get("Authorization") or ""
        if not header.startswith("Bearer "):
            return None
        email = STATE.tokens.get(header[7:].strip())
        return STATE.users.get(email) if email else None

    def log_message(self, fmt: str, *args) -> None:  # 標準出力を見やすく
        print(f"[{datetime.now():%H:%M:%S}] {self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")

    # -- routing ----------------------------------------------------------
    def do_GET(self) -> None:
        url = urlparse(self.path)
        path = url.path.rstrip("/") or "/"
        query = parse_qs(url.query)

        if path == "/api/v1/health":
            return self.send_json({"status": "ok", "time": now()})
        if path == "/api/v1/interviews":
            q = (query.get("q") or [""])[0].strip()
            items = [
                with_media(self.base, {k: v for k, v in i.items() if k != "blocks"})
                for i in INTERVIEWS
                if not q or q in i["title"] or q in i.get("excerpt", "") or q in i.get("company", "")
            ]
            return self.send_json({"items": items, "total": len(items)})
        match = re.fullmatch(r"/api/v1/interviews/([a-z0-9-]+)", path)
        if match:
            item = next((i for i in INTERVIEWS if i["slug"] == match.group(1)), None)
            return self.send_json(with_media(self.base, item)) if item else self.error(404, "not found")
        if path == "/api/v1/topics":
            return self.send_json({"items": TOPICS, "total": len(TOPICS)})
        match = re.fullmatch(r"/api/v1/topics/(\d+)", path)
        if match:
            item = next((t for t in TOPICS if t["id"] == int(match.group(1))), None)
            return self.send_json(item) if item else self.error(404, "not found")
        if path == "/api/v1/me":
            user = self.current_user()
            return self.send_json(public_user(user)) if user else self.error(401, "unauthorized")
        if path.startswith("/media/"):
            return self.serve_media(path[len("/media/"):])
        if path in ("/", "/admin"):
            return self.serve_admin()
        return self.error(404, "not found")

    def do_POST(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        body = self.read_json()

        if path == "/api/v1/auth/code":
            email = str(body.get("email", "")).strip().lower()
            if not EMAIL_RE.match(email):
                print(f"  メールアドレスの形式エラー: {email!r}")
                return self.error(422, "メールアドレスの形式が正しくありません")
            code = f"{secrets.randbelow(1_000_000):06d}"
            with STATE.lock:
                STATE.codes[email] = code
            print(f"  確認コード {email}: {code}")
            # 試作のため、メール送信の代わりに応答へコードを含める
            return self.send_json({"sent": True, "debugCode": code})
        if path == "/api/v1/auth/verify":
            email = str(body.get("email", "")).strip().lower()
            code = str(body.get("code", "")).strip()
            with STATE.lock:
                if not code or STATE.codes.get(email) != code:
                    return self.error(422, "確認コードが正しくありません")
                del STATE.codes[email]
                user = STATE.users.setdefault(email, {
                    "email": email,
                    "displayName": "",
                    "statuses": [],
                    "interests": [],
                    "areas": [],
                    "profileCompleted": False,
                    "createdAt": now(),
                })
                token = secrets.token_urlsafe(24)
                STATE.tokens[token] = email
            return self.send_json({"token": token, "user": public_user(user)})
        if path == "/api/v1/auth/logout":
            header = self.headers.get("Authorization") or ""
            with STATE.lock:
                STATE.tokens.pop(header[7:].strip(), None)
            return self.send_json({"ok": True})
        if path == "/api/v1/devices":
            token = str(body.get("token", "")).strip()
            platform = str(body.get("platform", "")).strip()
            if not token or platform not in ("ios", "ios-simulator", "android"):
                return self.error(422, "token と platform が必要です")
            user = self.current_user()
            with STATE.lock:
                STATE.devices[token] = {
                    "platform": platform,
                    "user": user["email"] if user else None,
                    "registeredAt": now(),
                }
            print(f"  通知先を登録 {platform}: {token[:16]}…")
            return self.send_json({"registered": True})
        if path == "/api/v1/admin/push":
            return self.send_json(*self.push(body))
        return self.error(404, "not found")

    def do_PUT(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        if path != "/api/v1/me":
            return self.error(404, "not found")
        user = self.current_user()
        if not user:
            return self.error(401, "unauthorized")
        body = self.read_json()
        with STATE.lock:
            name = str(body.get("displayName", user["displayName"])).strip()[:40]
            user["displayName"] = name
            for key in ("statuses", "interests", "areas"):
                value = body.get(key, user[key])
                if isinstance(value, list):
                    user[key] = [str(v)[:40] for v in value][:12]
            user["profileCompleted"] = bool(name and user["statuses"])
        return self.send_json(public_user(user))

    # -- media / admin / push ---------------------------------------------
    def serve_media(self, relative: str) -> None:
        target = (DATA_DIR / "images" / unquote(relative)).resolve()
        if not target.is_file() or (DATA_DIR / "images").resolve() not in target.parents:
            return self.error(404, "not found")
        data = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=86400")
        self.end_headers()
        self.wfile.write(data)

    def push(self, body: dict) -> tuple[dict, int]:
        slug = str(body.get("slug", ""))
        item = next((i for i in INTERVIEWS if i["slug"] == slug), None)
        if not item:
            return {"error": "記事が見つかりません"}, 404
        payload = {
            "Simulator Target Bundle": BUNDLE_ID,
            "aps": {
                "alert": {"title": "新着インタビュー", "body": item["title"]},
                "sound": "default",
            },
            "link": f"vamos://app/interviews/{slug}",
        }
        results = []
        devices = dict(STATE.devices)
        for token, device in devices.items():
            if device["platform"] == "ios-simulator":
                with tempfile.NamedTemporaryFile("w", suffix=".apns", delete=False, encoding="utf-8") as f:
                    json.dump(payload, f, ensure_ascii=False)
                proc = subprocess.run(["xcrun", "simctl", "push", "booted", BUNDLE_ID, f.name],
                                      capture_output=True, text=True, timeout=20)
                Path(f.name).unlink(missing_ok=True)
                ok = proc.returncode == 0
                results.append({"device": token[:16], "sent": ok, "detail": (proc.stderr or proc.stdout).strip()[:200]})
            else:
                # 実機・Android は本番では FCM / APNs から配信する（試作では未対応）
                results.append({"device": token[:16], "sent": False, "detail": "FCM/APNs 未設定"})
        entry = {"time": now(), "slug": slug, "title": item["title"], "results": results}
        with STATE.lock:
            STATE.push_log.insert(0, entry)
        print(f"  通知を配信 {slug}: {results}")
        return {"payload": payload, "results": results}, 200

    def serve_admin(self) -> None:
        rows = "".join(
            f'<li><span>{i["date"]}</span> {htmllib.escape(i["title"])}'
            f'<button onclick="send(\'{i["slug"]}\', this)">通知で配信</button></li>'
            for i in INTERVIEWS
        )
        devices = "".join(
            f"<li>{d['platform']} / {htmllib.escape(d['user'] or 'ゲスト')} / {htmllib.escape(t[:16])}… / {d['registeredAt']}</li>"
            for t, d in STATE.devices.items()
        ) or "<li>まだありません（アプリのマイページで通知をオンにしてください）</li>"
        users = "".join(
            f"<li>{htmllib.escape(u['displayName'] or '（未設定）')} / {htmllib.escape(u['email'])} / {htmllib.escape(', '.join(u['statuses']) or '-')}</li>"
            for u in STATE.users.values()
        ) or "<li>まだありません</li>"
        html = f"""<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>VAMOS モックAPI 管理</title>
<style>
body{{font-family:-apple-system,"Hiragino Sans",sans-serif;background:#eef1f6;color:#1a1a1a;margin:0;padding:24px}}
h1{{font-size:20px}} h2{{font-size:15px;color:#1b96d8;letter-spacing:.1em;margin-top:28px}}
ul{{background:#fff;border:1px solid #e8ecf2;border-radius:12px;list-style:none;padding:8px 16px}}
li{{padding:10px 0;border-bottom:1px solid #e8ecf2;font-size:14px;display:flex;gap:10px;align-items:center}}
li:last-child{{border:0}} li span{{color:#8e95a3;font-size:12px;white-space:nowrap}}
button{{margin-left:auto;white-space:nowrap;border:0;border-radius:999px;padding:8px 14px;color:#fff;
background:linear-gradient(135deg,#2ba8e8,#1f80cf);font-weight:700;cursor:pointer}}
#log{{font-size:12px;color:#5c6370;white-space:pre-wrap}}
</style></head><body>
<h1>VAMOS モックAPI 管理画面（試作）</h1>
<p>編集部が記事を公開したときの「プッシュ通知の配信」を再現します。</p>
<h2>通知先の端末</h2><ul>{devices}</ul>
<h2>会員</h2><ul>{users}</ul>
<h2>インタビュー</h2><ul>{rows}</ul>
<div id="log"></div>
<script>
async function send(slug, btn) {{
  btn.disabled = true; btn.textContent = '配信中…';
  const res = await fetch('/api/v1/admin/push', {{method: 'POST', headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify({{slug}})}});
  const data = await res.json();
  document.getElementById('log').textContent = JSON.stringify(data.results || data, null, 2);
  btn.textContent = '配信しました'; setTimeout(() => {{ btn.disabled = false; btn.textContent = '通知で配信'; }}, 2000);
}}
</script></body></html>"""
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"VAMOS mock API: http://localhost:{args.port}  (interviews={len(INTERVIEWS)}, topics={len(TOPICS)})")
    server.serve_forever()


if __name__ == "__main__":
    main()
