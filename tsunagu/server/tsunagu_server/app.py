"""アプリ本体（ルーティング・認証・静的ページ）と HTTP サーバー。"""
from __future__ import annotations

import mimetypes
import os
import sqlite3
import sys
import threading
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional

from . import admin, auth, forest, sns, uploads
from .accounts import hash_token
from .config import Config
from .db import connect, init_db, now
from .web import MAX_BODY, ApiError, Ctx, RateLimiter, Request, Response, Router

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")

# 静的ページ（パス → static/ 内のファイル）
PAGES = {
    "/": "index.html",
    "/admin": "admin/index.html",
    "/admin/": "admin/index.html",
    "/passkey/login": "passkey/login.html",
    "/passkey/register": "passkey/register.html",
}

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}
PAGE_CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; "
            "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'")


class App:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.rate = RateLimiter()
        self.router = Router()
        for module in (auth, sns, forest, uploads, admin):
            self.router.routes.extend(module.router.routes)
        self._log_lock = threading.Lock()
        init_db(cfg.db_path)

    def log(self, message: str) -> None:
        with self._log_lock:
            sys.stderr.write(message + "\n")

    # ------------------------------------------------------------- 認証
    def authenticate(self, ctx: Ctx, level: str) -> None:
        token = ctx.req.bearer()
        if not token:
            raise ApiError(401, "unauthorized", "ログインしてください")
        row = ctx.db.execute(
            "SELECT * FROM sessions WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?",
            (hash_token(token), now())).fetchone()
        if row is None:
            raise ApiError(401, "session_expired", "ログインの有効期限が切れました。もう一度ログインしてください")
        user = ctx.db.execute("SELECT * FROM users WHERE id = ?", (row["user_id"],)).fetchone()
        company = ctx.db.execute("SELECT * FROM companies WHERE id = ?", (user["company_id"],)).fetchone()
        if user["status"] != "active" or company["status"] != "active":
            ctx.db.execute("UPDATE sessions SET revoked_at = ? WHERE id = ?", (now(), row["id"]))
            ctx.db.commit()
            raise ApiError(401, "session_expired", "このアカウントは利用できません。管理者にお問い合わせください")
        if level in ("user", "admin") and row["scope"] != "full":
            raise ApiError(403, "password_change_required", "パスワードを再設定してください")
        if level == "admin" and user["role"] != "admin":
            raise ApiError(403, "forbidden", "管理者のみが使える機能です")
        if now() - row["last_seen_at"] > 60:
            ctx.db.execute("UPDATE sessions SET last_seen_at = ? WHERE id = ?", (now(), row["id"]))
        ctx.session, ctx.user, ctx.company = row, user, company

    # ------------------------------------------------------------- 入口
    def handle(self, method: str, raw_path: str, headers: Dict[str, str], body: bytes, ip: str) -> Response:
        req = Request.build(method, raw_path, headers, body, ip)
        if req.path.startswith("/api/"):
            resp = self._handle_api(req)
        else:
            resp = self._handle_static(req)
        for key, value in SECURITY_HEADERS.items():
            resp.headers.setdefault(key, value)
        return resp

    def _handle_api(self, req: Request) -> Response:
        db: Optional[sqlite3.Connection] = None
        try:
            handler, params, level = self.router.match(req.method, req.path)
            req.params = params
            if req.method in ("POST", "PUT", "PATCH") and req.body and req.path != "/api/uploads":
                ctype = req.headers.get("content-type", "")
                if not ctype.startswith("application/json"):
                    raise ApiError(415, "unsupported_media_type", "JSON で送信してください")
            db = connect(self.cfg.db_path)
            ctx = Ctx(req=req, db=db, app=self)
            if level != "public":
                self.authenticate(ctx, level)
            resp = handler(ctx)
            db.commit()
            return resp
        except ApiError as err:
            if db is not None:
                db.rollback()
            return Response.error(err)
        except Exception:  # noqa: BLE001 - 想定外のエラーは 500 で返す
            if db is not None:
                db.rollback()
            self.log(traceback.format_exc())
            return Response.error(ApiError(500, "server_error", "サーバーでエラーが発生しました"))
        finally:
            if db is not None:
                db.close()

    def _handle_static(self, req: Request) -> Response:
        if req.method not in ("GET", "HEAD"):
            return Response.error(ApiError(405, "method_not_allowed", "この操作はできません"))
        rel = PAGES.get(req.path)
        if rel is None and req.path.startswith("/static/"):
            rel = req.path[len("/static/"):]
        if rel is None:
            return Response(404, {"Content-Type": "text/plain; charset=utf-8"}, "見つかりません".encode("utf-8"))
        full = os.path.normpath(os.path.join(STATIC_DIR, rel))
        if not full.startswith(STATIC_DIR + os.sep) or not os.path.isfile(full):
            return Response(404, {"Content-Type": "text/plain; charset=utf-8"}, "見つかりません".encode("utf-8"))
        with open(full, "rb") as fh:
            data = fh.read()
        ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/javascript", "image/svg+xml"):
            ctype += "; charset=utf-8"
        headers = {"Content-Type": ctype, "Cache-Control": "no-cache"}
        if full.endswith(".html"):
            headers["Content-Security-Policy"] = PAGE_CSP
        return Response(200, headers, data)


def make_handler(app: App) -> type:
    class Handler(BaseHTTPRequestHandler):
        server_version = "tsunagu"
        sys_version = ""
        protocol_version = "HTTP/1.1"

        def _client_ip(self) -> str:
            if app.cfg.trust_proxy:
                forwarded = self.headers.get("X-Forwarded-For", "")
                if forwarded:
                    return forwarded.split(",")[0].strip()
            return self.client_address[0]

        def _dispatch(self) -> None:
            length_header = self.headers.get("Content-Length")
            if self.headers.get("Transfer-Encoding"):
                self._send(Response.error(ApiError(411, "length_required", "Content-Length が必要です")))
                return
            try:
                length = int(length_header or 0)
            except ValueError:
                length = -1
            if length < 0 or length > MAX_BODY:
                self._send(Response.error(ApiError(413, "too_large", "送信データが大きすぎます")))
                return
            body = self.rfile.read(length) if length else b""
            resp = app.handle(self.command, self.path, dict(self.headers.items()), body, self._client_ip())
            self._send(resp)

        def _send(self, resp: Response) -> None:
            self.send_response(resp.status)
            for key, value in resp.headers.items():
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(resp.body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(resp.body)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = _dispatch

        def log_message(self, fmt: str, *args: object) -> None:  # トークン等を出さないよう簡潔に
            path = self.path.split("?", 1)[0]
            app.log("%s %s %s" % (self.command, path, args[1] if len(args) > 1 else ""))

    return Handler


def serve(cfg: Config, host: str, port: int) -> None:
    app = App(cfg)
    httpd = ThreadingHTTPServer((host, port), make_handler(app))
    httpd.daemon_threads = True
    app.log("M サーバー起動: http://%s:%d  （公開URL: %s / RP ID: %s / メール: %s）"
            % (host, port, cfg.public_url, cfg.rp_id, cfg.mail_mode))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
