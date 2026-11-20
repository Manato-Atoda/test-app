"""アカウント発行通知書（PDF）の生成。

外部ライブラリを使わず PDF を直接組み立てる。日本語は PDF 標準の CJK フォント
（HeiseiKakuGo-W5 / Adobe-Japan1）を埋め込まずに指定するので、ファイルは数 KB で済み、
閲覧側（プレビュー・Acrobat・Chrome / Edge）の日本語フォントで表示される。
英数字の ID・パスワードは等幅の Courier で表示して読み間違いを減らす。
"""
from __future__ import annotations

import zlib
from dataclasses import dataclass
from typing import List, Optional, Tuple

PAGE_W, PAGE_H = 595.28, 841.89  # A4（pt）
MARGIN = 56.0


@dataclass
class AccountNotice:
    company_name: str
    company_code: str
    display_name: str
    department: str
    employee_code: str
    email: Optional[str]
    temporary_password: str
    expires_at_text: str      # 例: 2026年11月23日(月) 10:00
    issued_at_text: str       # 例: 2026年11月20日
    login_url: str
    min_length: int = 8
    require_symbol: bool = False
    service_name: str = "M"


def _jp_hex(text: str) -> str:
    """UniJIS-UCS2-H 用の UTF-16BE（BMP 外の文字は「〓」に置換）。"""
    out = []
    for ch in text:
        code = ord(ch)
        if code > 0xFFFF:
            code = 0x3013
        out.append("%04X" % code)
    return "<" + "".join(out) + ">"


def _ascii_literal(text: str) -> str:
    safe = text.encode("latin-1", "replace").decode("latin-1")
    return "(" + safe.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


def _jp_width(text: str, size: float) -> float:
    return sum((0.5 if ord(ch) < 0x80 or 0xFF61 <= ord(ch) <= 0xFF9F else 1.0) for ch in text) * size


class _Page:
    def __init__(self) -> None:
        self.ops: List[str] = []

    # 日本語（Type0 / CID フォント）
    def jp(self, x: float, y: float, text: str, size: float = 10.5,
           color: Tuple[float, float, float] = (0.13, 0.15, 0.2)) -> None:
        self.ops.append("BT %.3f %.3f %.3f rg /F1 %.2f Tf %.2f %.2f Td %s Tj ET"
                        % (color + (size, x, y, _jp_hex(text))))

    # 英数字（Courier）
    def mono(self, x: float, y: float, text: str, size: float = 12, bold: bool = True,
             color: Tuple[float, float, float] = (0.05, 0.07, 0.12)) -> None:
        self.ops.append("BT %.3f %.3f %.3f rg /%s %.2f Tf %.2f %.2f Td %s Tj ET"
                        % (color + ("F2" if bold else "F3", size, x, y, _ascii_literal(text))))

    def rect(self, x: float, y: float, w: float, h: float, *, fill: Optional[Tuple[float, float, float]] = None,
             stroke: Optional[Tuple[float, float, float]] = None, width: float = 0.8) -> None:
        parts = ["q", "%.2f w" % width]
        if fill:
            parts.append("%.3f %.3f %.3f rg" % fill)
        if stroke:
            parts.append("%.3f %.3f %.3f RG" % stroke)
        parts.append("%.2f %.2f %.2f %.2f re" % (x, y, w, h))
        parts.append("B" if fill and stroke else ("f" if fill else "S"))
        parts.append("Q")
        self.ops.append(" ".join(parts))

    def line(self, x1: float, y1: float, x2: float, y2: float, *, width: float = 0.6,
             color: Tuple[float, float, float] = (0.75, 0.78, 0.84), dash: bool = False) -> None:
        self.ops.append("q %.2f w %.3f %.3f %.3f RG %s %.2f %.2f m %.2f %.2f l S Q"
                        % ((width,) + color + ("[3 3] 0 d" if dash else "[] 0 d", x1, y1, x2, y2)))

    def stream(self) -> bytes:
        return "\n".join(self.ops).encode("latin-1")


BRAND = (0.20, 0.33, 0.82)
MUTED = (0.42, 0.45, 0.52)


def _wrap(text: str, size: float, max_width: float) -> List[str]:
    lines, current = [], ""
    for ch in text:
        if _jp_width(current + ch, size) > max_width:
            lines.append(current)
            current = ch
        else:
            current += ch
    if current:
        lines.append(current)
    return lines


def _draw_notice(page: _Page, n: AccountNotice) -> None:
    left, right = MARGIN, PAGE_W - MARGIN
    width = right - left
    y = PAGE_H - MARGIN

    # ヘッダー
    page.rect(0, PAGE_H - 10, PAGE_W, 10, fill=BRAND)
    page.jp(left, y - 6, "社内SNS「%s」" % n.service_name, 10, MUTED)
    issued = "発行日 " + n.issued_at_text
    page.jp(right - _jp_width(issued, 9.5), y - 6, issued, 9.5, MUTED)
    page.jp(left, y - 36, "アカウント発行のお知らせ", 22, (0.08, 0.1, 0.16))
    page.line(left, y - 50, right, y - 50, width=1.2, color=BRAND)

    y -= 86
    page.jp(left, y, "%s　様" % n.display_name, 15)
    if n.department:
        page.jp(left, y - 20, "%s　%s" % (n.company_name, n.department), 10, MUTED)
    else:
        page.jp(left, y - 20, n.company_name, 10, MUTED)

    y -= 50
    intro = "%sの社内SNS「%s」のアカウントを発行しました。下記の情報でログインし、" \
            "初回ログイン時に新しいパスワードを設定してください。" % (n.company_name, n.service_name)
    for row in _wrap(intro, 10.5, width):
        page.jp(left, y, row, 10.5)
        y -= 17

    # ログイン情報の枠
    y -= 10
    rows = [
        ("企業コード", n.company_code, 15),
        ("社員コード", n.employee_code, 15),
        ("メールアドレス", n.email or "", 12),
        ("仮パスワード", n.temporary_password, 19),
    ]
    row_h = 34.0
    box_h = row_h * len(rows) + 58
    top = y
    page.rect(left, top - box_h, width, box_h, fill=(0.96, 0.97, 1.0), stroke=(0.78, 0.82, 0.93))
    ry = top - 28
    for i, (label, value, size) in enumerate(rows):
        page.jp(left + 18, ry, label, 10.5, MUTED)
        if label == "メールアドレス" and not value:
            page.jp(left + 140, ry, "（登録なし・社員コードでログイン）", 10.5, MUTED)
        else:
            page.mono(left + 140, ry - 1, value, size)
        if i < len(rows) - 1:
            page.line(left + 14, ry - 13, right - 14, ry - 13, color=(0.86, 0.88, 0.94))
        ry -= row_h
    page.jp(left + 18, ry + 6, "仮パスワードの有効期限：%s まで" % n.expires_at_text, 10.5, (0.75, 0.16, 0.16))
    page.jp(left + 18, ry - 10, "※ 大文字と小文字を区別します。ハイフン（-）も入力してください。", 9, MUTED)
    y = top - box_h - 30

    # 手順
    page.jp(left, y, "ログイン手順", 12.5, BRAND)
    y -= 22
    rule = "%d文字以上・英字と数字を必ず含む・記号も使えます" % n.min_length
    if n.require_symbol:
        rule = "%d文字以上・英字と数字と記号を必ず含む" % n.min_length
    steps = [
        "1.  アプリ「%s」を開きます（iPhone / Android / Mac / Windows）。" % n.service_name,
        "2.  企業コード、社員コード（またはメールアドレス）、仮パスワードを入力してログインします。",
        "3.  新しいパスワードを設定します（%s）。" % rule,
        "4.  メニューの「パスキー」で登録すると、次回から指紋・顔認証でログインできます。",
    ]
    for step in steps:
        for j, row in enumerate(_wrap(step, 10.5, width - 10)):
            page.jp(left + (16 if j else 0), y, row, 10.5)
            y -= 17
        y -= 3
    page.jp(left, y - 2, "接続先：", 9.5, MUTED)
    page.mono(left + 42, y - 2, n.login_url, 9.5, bold=False, color=MUTED)

    # 注意
    y -= 34
    page.jp(left, y, "取り扱いのご注意", 12.5, (0.75, 0.16, 0.16))
    y -= 22
    cautions = [
        "・この通知書は本人以外に見せたり、写真に撮って送ったりしないでください。",
        "・パスワードを設定したら、この通知書はシュレッダー等で確実に破棄してください。",
        "・有効期限を過ぎた場合や紛失した場合は、社内の管理者に再発行を依頼してください。",
        "・パスワードは管理者を含め誰にも教えないでください。管理者が尋ねることはありません。",
    ]
    for c in cautions:
        for row in _wrap(c, 10, width):
            page.jp(left, y, row, 10)
            y -= 16

    # フッター
    page.line(left, MARGIN + 18, right, MARGIN + 18, dash=True)
    page.jp(left, MARGIN, "%s　社内SNS管理者" % n.company_name, 9, MUTED)
    note = "機密：本人限り"
    page.jp(right - _jp_width(note, 9), MARGIN, note, 9, (0.75, 0.16, 0.16))


def build_account_notices_pdf(notices: List[AccountNotice], title: str = "アカウント発行のお知らせ") -> bytes:
    """1 人 1 ページの PDF を作る。"""
    objects: List[bytes] = []

    def add(obj: bytes) -> int:
        objects.append(obj)
        return len(objects)

    catalog_id = add(b"")  # 後で差し替え
    pages_id = add(b"")
    descriptor_id = add(
        b"<< /Type /FontDescriptor /FontName /HeiseiKakuGo-W5 /Flags 4 /FontBBox [-92 -250 1010 922] "
        b"/ItalicAngle 0 /Ascent 752 /Descent -221 /CapHeight 737 /StemV 114 /XHeight 553 >>")
    cid_font_id = add(
        ("<< /Type /Font /Subtype /CIDFontType0 /BaseFont /HeiseiKakuGo-W5 "
         "/CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> "
         "/FontDescriptor %d 0 R /DW 1000 /W [1 95 500 231 389 500 631 631 500] >>" % descriptor_id).encode())
    font_jp = add(("<< /Type /Font /Subtype /Type0 /BaseFont /HeiseiKakuGo-W5 /Encoding /UniJIS-UCS2-H "
                   "/DescendantFonts [%d 0 R] >>" % cid_font_id).encode())
    font_mono_b = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold /Encoding /WinAnsiEncoding >>")
    font_mono = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")
    resources = ("<< /Font << /F1 %d 0 R /F2 %d 0 R /F3 %d 0 R >> >>" % (font_jp, font_mono_b, font_mono)).encode()

    page_ids = []
    for notice in notices:
        page = _Page()
        _draw_notice(page, notice)
        raw = zlib.compress(page.stream())
        content_id = add(b"<< /Length %d /Filter /FlateDecode >>\nstream\n" % len(raw) + raw + b"\nendstream")
        page_ids.append(add(
            ("<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %.2f %.2f] /Contents %d 0 R /Resources "
             % (pages_id, PAGE_W, PAGE_H, content_id)).encode() + resources + b" >>"))

    objects[catalog_id - 1] = ("<< /Type /Catalog /Pages %d 0 R >>" % pages_id).encode()
    objects[pages_id - 1] = ("<< /Type /Pages /Kids [%s] /Count %d >>"
                             % (" ".join("%d 0 R" % p for p in page_ids), len(page_ids))).encode()
    # 文書情報のタイトルは BOM 付き UTF-16BE
    info_id = add(("<< /Title %s /Producer (tsunagu) >>" % _jp_hex("﻿" + title)).encode())

    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + obj + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += (b"trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n"
            % (len(objects) + 1, catalog_id, info_id, xref))
    return bytes(out)
