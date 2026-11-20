"""HTTP の小さな土台（リクエスト・レスポンス・ルーティング・エラー）。"""
from __future__ import annotations

import json
import re
import sqlite3
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Callable, Deque, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, quote

MAX_BODY = 2 * 1024 * 1024


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, **extra: Any) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra


@dataclass
class Request:
    method: str
    path: str
    query: Dict[str, str]
    headers: Dict[str, str]  # 小文字のキー
    body: bytes
    ip: str
    params: Dict[str, Any] = field(default_factory=dict)
    _json: Any = None

    @classmethod
    def build(cls, method: str, raw_path: str, headers: Dict[str, str], body: bytes, ip: str) -> "Request":
        path, _, qs = raw_path.partition("?")
        query = {k: v[0] for k, v in parse_qs(qs, keep_blank_values=True).items()}
        return cls(method.upper(), path or "/", query, {k.lower(): v for k, v in headers.items()}, body, ip)

    def json(self) -> Dict[str, Any]:
        if self._json is None:
            if not self.body:
                self._json = {}
            else:
                try:
                    self._json = json.loads(self.body.decode("utf-8"))
                except (UnicodeDecodeError, ValueError):
                    raise ApiError(400, "invalid_json", "リクエストの形式が正しくありません")
            if not isinstance(self._json, dict):
                raise ApiError(400, "invalid_json", "リクエストの形式が正しくありません")
        return self._json

    def str_field(self, name: str, *, required: bool = True, max_len: int = 200, label: str = "") -> str:
        value = self.json().get(name, "")
        if value is None:
            value = ""
        if not isinstance(value, str):
            raise ApiError(400, "invalid_field", "%sの形式が正しくありません" % (label or name), field=name)
        value = value.strip()
        if required and not value:
            raise ApiError(400, "required", "%sを入力してください" % (label or name), field=name)
        if len(value) > max_len:
            raise ApiError(400, "too_long", "%sは%d文字以内にしてください" % (label or name, max_len), field=name)
        return value

    def bearer(self) -> Optional[str]:
        auth = self.headers.get("authorization", "")
        if auth.lower().startswith("bearer "):
            token = auth[7:].strip()
            return token or None
        return None

    def int_query(self, name: str, default: Optional[int] = None, *, lo: int = 1, hi: int = 1 << 62) -> Optional[int]:
        raw = self.query.get(name)
        if raw in (None, ""):
            return default
        try:
            value = int(raw)
        except ValueError:
            raise ApiError(400, "invalid_query", "%s の値が正しくありません" % name)
        return max(lo, min(hi, value))


@dataclass
class Response:
    status: int = 200
    headers: Dict[str, str] = field(default_factory=dict)
    body: bytes = b""

    @classmethod
    def json(cls, data: Any, status: int = 200) -> "Response":
        return cls(status, {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"},
                   json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

    @classmethod
    def empty(cls, status: int = 204) -> "Response":
        return cls(status, {"Cache-Control": "no-store"}, b"")

    @classmethod
    def download(cls, data: bytes, content_type: str, filename: str) -> "Response":
        ascii_name = re.sub(r"[^A-Za-z0-9._-]", "_", filename)
        return cls(200, {
            "Content-Type": content_type,
            "Content-Disposition": "attachment; filename=\"%s\"; filename*=UTF-8''%s" % (ascii_name, quote(filename)),
            "Cache-Control": "no-store",
        }, data)

    @classmethod
    def error(cls, err: ApiError) -> "Response":
        payload = {"code": err.code, "message": err.message}
        payload.update(err.extra)
        return cls.json({"error": payload}, err.status)


@dataclass
class Ctx:
    """1 リクエスト分の文脈。"""
    req: Request
    db: sqlite3.Connection
    app: Any
    user: Optional[sqlite3.Row] = None
    company: Optional[sqlite3.Row] = None
    session: Optional[sqlite3.Row] = None

    @property
    def cfg(self) -> Any:
        return self.app.cfg

    @property
    def uid(self) -> int:
        assert self.user is not None
        return int(self.user["id"])

    @property
    def cid(self) -> int:
        assert self.company is not None
        return int(self.company["id"])

    @property
    def is_admin(self) -> bool:
        return self.user is not None and self.user["role"] == "admin"


Handler = Callable[[Ctx], Response]
_PARAM = re.compile(r"\{(\w+)(?::(int))?\}")


class Router:
    def __init__(self) -> None:
        self.routes: List[Tuple[str, "re.Pattern[str]", Handler, str]] = []

    def add(self, method: str, pattern: str, handler: Handler, auth: str) -> None:
        def repl(m: "re.Match[str]") -> str:
            if m.group(2) == "int":
                return r"(?P<%s>\d{1,18})" % m.group(1)
            return r"(?P<%s>[^/]+)" % m.group(1)
        regex = re.compile("^" + _PARAM.sub(repl, pattern) + "$")
        self.routes.append((method, regex, handler, auth))

    def route(self, method: str, pattern: str, auth: str = "user") -> Callable[[Handler], Handler]:
        """auth: public（不要） / limited（仮パスワード中も可） / user / admin"""
        def deco(fn: Handler) -> Handler:
            self.add(method, pattern, fn, auth)
            return fn
        return deco

    def match(self, method: str, path: str) -> Tuple[Handler, Dict[str, Any], str]:
        allowed = False
        for m, regex, handler, auth in self.routes:
            found = regex.match(path)
            if not found:
                continue
            if m != method:
                allowed = True
                continue
            params = {k: (int(v) if v.isdigit() else v) for k, v in found.groupdict().items()}
            return handler, params, auth
        if allowed:
            raise ApiError(405, "method_not_allowed", "この操作はできません")
        raise ApiError(404, "not_found", "見つかりません")


class RateLimiter:
    """IP ごとの簡易レート制限（同一プロセス内のみ）。"""

    def __init__(self) -> None:
        self._hits: Dict[str, Deque[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window: float) -> None:
        current = time.monotonic()
        with self._lock:
            hits = self._hits.setdefault(key, deque())
            while hits and hits[0] <= current - window:
                hits.popleft()
            if len(hits) >= limit:
                retry = int(hits[0] + window - current) + 1
                raise ApiError(429, "rate_limited", "試行回数が多すぎます。しばらく待ってからやり直してください",
                               retry_after_seconds=retry)
            hits.append(current)
            if len(self._hits) > 50000:
                self._hits.clear()
