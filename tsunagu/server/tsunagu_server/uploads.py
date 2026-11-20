"""画像のアップロードと配信。

- 受け取るのは JPEG / PNG / WebP だけ。Content-Type ではなく、ファイルの先頭（マジックバイト）で判定する。
- 縦横の大きさはヘッダーから読む（画像の加工はアプリ側で縮小してから送る）。
- 配信はログイン中・同じ企業の人だけ。URL を知っていても他社や未ログインでは見られない。
"""
from __future__ import annotations

import os
import secrets
import struct
from typing import Optional, Tuple

from .db import now
from .web import ApiError, Ctx, Response, Router

router = Router()

MAX_UPLOAD = 8 * 1024 * 1024
MAX_SIDE = 8000
EXTENSIONS = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}


def sniff(data: bytes) -> Optional[str]:
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def image_size(data: bytes, mime: str) -> Optional[Tuple[int, int]]:
    try:
        if mime == "image/png":
            width, height = struct.unpack(">II", data[16:24])
            return width, height
        if mime == "image/webp":
            chunk = data[12:16]
            if chunk == b"VP8X":
                width = int.from_bytes(data[24:27], "little") + 1
                height = int.from_bytes(data[27:30], "little") + 1
                return width, height
            if chunk == b"VP8L":
                bits = int.from_bytes(data[21:25], "little")
                return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
            if chunk == b"VP8 ":
                width, height = struct.unpack("<HH", data[26:30])
                return width & 0x3FFF, height & 0x3FFF
            return None
        # JPEG: SOF マーカーを探す
        pos = 2
        while pos + 9 < len(data):
            if data[pos] != 0xFF:
                pos += 1
                continue
            marker = data[pos + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                pos += 2
                continue
            length = struct.unpack(">H", data[pos + 2:pos + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack(">HH", data[pos + 5:pos + 9])
                return width, height
            pos += 2 + length
    except (struct.error, IndexError):
        return None
    return None


def upload_dir(cfg) -> str:
    return os.path.join(os.path.dirname(os.path.abspath(cfg.db_path)), "uploads")


def image_json(row) -> dict:
    return {"id": row["id"], "url": "/api/uploads/%s" % row["id"], "width": row["width"], "height": row["height"]}


def own_upload(ctx: Ctx, upload_id) -> dict:
    """自分がアップロードした画像だけを投稿・プロフィールに使える。"""
    if not isinstance(upload_id, str):
        raise ApiError(400, "invalid_image", "画像の指定が正しくありません")
    row = ctx.db.execute("SELECT * FROM uploads WHERE id = ? AND user_id = ? AND company_id = ?",
                         (upload_id, ctx.uid, ctx.cid)).fetchone()
    if row is None:
        raise ApiError(400, "invalid_image", "画像が見つかりません。もう一度アップロードしてください")
    return row


@router.route("POST", "/api/uploads")
def upload(ctx: Ctx) -> Response:
    data = ctx.req.body
    if not data:
        raise ApiError(400, "required", "画像を選んでください")
    if len(data) > MAX_UPLOAD:
        raise ApiError(413, "too_large", "画像は 8MB 以内にしてください")
    mime = sniff(data)
    if mime is None:
        raise ApiError(415, "unsupported_image", "JPEG・PNG・WebP の画像を選んでください")
    size = image_size(data, mime)
    if size is None or not (0 < size[0] <= MAX_SIDE and 0 < size[1] <= MAX_SIDE):
        raise ApiError(415, "unsupported_image", "画像を読み取れませんでした")
    ctx.app.rate.check("upload:%d" % ctx.uid, limit=60, window=600)
    upload_id = secrets.token_urlsafe(18)
    directory = os.path.join(upload_dir(ctx.cfg), str(ctx.cid))
    os.makedirs(directory, exist_ok=True)
    rel = os.path.join(str(ctx.cid), "%s.%s" % (upload_id, EXTENSIONS[mime]))
    with open(os.path.join(upload_dir(ctx.cfg), rel), "wb") as fh:
        fh.write(data)
    ctx.db.execute("INSERT INTO uploads (id, company_id, user_id, mime, size, width, height, path, created_at)"
                   " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                   (upload_id, ctx.cid, ctx.uid, mime, len(data), size[0], size[1], rel, now()))
    row = ctx.db.execute("SELECT * FROM uploads WHERE id = ?", (upload_id,)).fetchone()
    return Response.json(image_json(row))


@router.route("GET", "/api/uploads/{id}")
def serve(ctx: Ctx) -> Response:
    row = ctx.db.execute("SELECT * FROM uploads WHERE id = ? AND company_id = ?",
                         (ctx.req.params["id"], ctx.cid)).fetchone()
    if row is None:
        raise ApiError(404, "not_found", "画像が見つかりません")
    path = os.path.join(upload_dir(ctx.cfg), row["path"])
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        raise ApiError(404, "not_found", "画像が見つかりません")
    return Response(200, {"Content-Type": row["mime"], "Cache-Control": "private, max-age=86400",
                          "Content-Security-Policy": "default-src 'none'; sandbox"}, data)
