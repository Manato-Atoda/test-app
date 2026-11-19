#!/usr/bin/env python3
"""RE_VAMOS（参照用のクローン）から、試作アプリ用のサンプルデータを書き出す。

RE_VAMOS 側のファイルは読み取るだけで、変更しない。
書き出したデータ（assets/vamos/）は Git の管理対象外。

使い方:
    python3 -I tool/import_vamos_data.py <RE_VAMOS のクローン> [--count 10]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = APP_ROOT / "assets" / "vamos"

# 画像の最大辺（px）。アプリを軽くするため縮小して取り込む
MAX_SIZE = {"hero": 1200, "body": 1200, "avatar": 240}


# --------------------------------------------------------------------------
# HTML → ブロック変換
# --------------------------------------------------------------------------
VOID_TAGS = {"img", "br", "hr", "source", "wbr", "input", "meta", "link", "path", "circle", "rect"}
SKIP_TAGS = {"svg", "video", "iframe", "script", "style", "noscript"}
TEXT_TAGS = {"p", "h2", "h3", "li", "blockquote", "figcaption"}
LINK_FIELDS = {"topic-link-title": "title", "topic-link-desc": "description", "topic-link-src": "source"}


class BlockParser(HTMLParser):
    """インタビュー・トピック本文の HTML を、アプリで描画するブロックに変換する。

    対応する部品:
      paragraph / heading / list / quote / image（figure・sg-media）/ divider
      speech（sg-speak：聞き手 q・取材相手 a の吹き出し）/ link（topic-link のリンクカード）
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[dict] = []
        self._depth = 0
        self._skip_until: int | None = None
        self._text: list[str] | None = None
        self._text_tag: str | None = None
        self._speech: dict | None = None
        self._speech_depth = 0
        self._link: dict | None = None
        self._link_field: str | None = None
        self._figure: dict | None = None
        self._list: list[str] | None = None

    # 自己終了タグ（<img/> など）は開始タグとしてだけ扱う
    def handle_startendtag(self, tag, attrs) -> None:
        self.handle_starttag(tag, attrs, void=True)

    def handle_starttag(self, tag, attrs, void: bool = False) -> None:
        void = void or tag in VOID_TAGS
        attrs = dict(attrs)
        classes = (attrs.get("class") or "").split()

        if self._skip_until is not None:
            if not void:
                self._depth += 1
            return
        if tag in SKIP_TAGS:
            if not void:
                self._depth += 1
                self._skip_until = self._depth
            return
        if not void:
            self._depth += 1

        if tag == "br":
            if self._text is not None:
                self._text.append("\n")
        elif tag == "hr":
            self.blocks.append({"type": "divider"})
        elif tag == "img":
            src = (attrs.get("src") or "").split("?")[0]
            if not src:
                return
            if self._speech is not None and not self._speech["avatar"]:
                self._speech["avatar"] = src
            elif self._figure is not None:
                self._figure["src"] = src
            else:
                self.blocks.append({"type": "image", "src": src, "caption": ""})
        elif tag == "div" and "sg-speak" in classes:
            self._speech = {
                "type": "speech",
                "role": "a" if "sg-speak--a" in classes else "q",
                "avatar": None,
                "paragraphs": [],
            }
            self._speech_depth = self._depth
        elif tag == "a" and "topic-link" in classes:
            self._link = {"type": "link", "title": "", "description": "", "source": "",
                          "url": attrs.get("href", "")}
        elif self._link is not None and any(c in LINK_FIELDS for c in classes):
            self._link_field = next(LINK_FIELDS[c] for c in classes if c in LINK_FIELDS)
            self._text, self._text_tag = [], tag
        elif tag == "figure":
            self._figure = {"type": "image", "src": "", "caption": ""}
        elif tag in ("ul", "ol"):
            self._list = []
        elif tag in TEXT_TAGS and self._text is None:
            self._text, self._text_tag = [], tag

    def handle_endtag(self, tag) -> None:
        if tag in VOID_TAGS:
            return
        depth = self._depth
        self._depth -= 1
        if self._skip_until is not None:
            if depth == self._skip_until:
                self._skip_until = None
            return

        if self._text is not None and tag == self._text_tag:
            text = re.sub(r"[ \t　]*\n[ \t　]*", "\n", "".join(self._text)).strip()
            self._text, self._text_tag = None, None
            self._finish_text(tag, text)
        elif tag == "div" and self._speech is not None and depth == self._speech_depth:
            if self._speech["paragraphs"]:
                self.blocks.append(self._speech)
            self._speech = None
        elif tag == "a" and self._link is not None:
            if self._link["title"]:
                self.blocks.append(self._link)
            self._link = None
        elif tag == "figure" and self._figure is not None:
            if self._figure["src"]:
                self.blocks.append(self._figure)
            self._figure = None
        elif tag in ("ul", "ol") and self._list is not None:
            if self._list:
                self.blocks.append({"type": "list", "items": self._list})
            self._list = None

    def _finish_text(self, tag: str, text: str) -> None:
        if self._link_field is not None:
            self._link[self._link_field] = text
            self._link_field = None
            return
        if not text:
            return
        if tag == "figcaption" and self._figure is not None:
            self._figure["caption"] = text
        elif tag == "li" and self._list is not None:
            self._list.append(text)
        elif tag in ("h2", "h3"):
            self.blocks.append({"type": "heading", "level": int(tag[1]), "text": text})
        elif tag == "blockquote":
            self.blocks.append({"type": "quote", "text": text})
        elif self._speech is not None:
            self._speech["paragraphs"].append(text)
        else:
            self.blocks.append({"type": "paragraph", "text": text})

    def handle_data(self, data: str) -> None:
        if self._skip_until is None and self._text is not None:
            self._text.append(data.replace("\n", ""))


def html_to_blocks(html: str) -> tuple[list[dict], list[str]]:
    parser = BlockParser()
    parser.feed(html)
    parser.close()
    images = [b.get("src") or b.get("avatar") for b in parser.blocks
              if b["type"] in ("image", "speech") and (b.get("src") or b.get("avatar"))]
    return parser.blocks, images


# --------------------------------------------------------------------------
# 入力の読み込み
# --------------------------------------------------------------------------
def load_interviews(repo: Path) -> list[dict]:
    source = (repo / "js" / "interview-data.js").read_text(encoding="utf-8")
    start = source.index("VAMOS_ARTICLES, [") + len("VAMOS_ARTICLES, ")
    end = source.rindex("]")
    return json.loads(source[start:end + 1])


def js_string(literal: str) -> str:
    """'...' 形式の JS 文字列リテラルの中身を復元する。"""
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), literal)


def load_topics(repo: Path) -> list[dict]:
    source = (repo / "js" / "topic-data.js").read_text(encoding="utf-8")
    labels = dict(re.findall(r"(\w+):\s*'([^']*)'", source[source.index("VAMOS_TOPIC_CAT"):].split("}")[0]))
    body = source[source.index("VAMOS_TOPICS"):]
    records = re.split(r"\n\s*\{\s*\n\s*id:", body)[1:]
    topics = []
    for record in records:
        record = "id:" + record
        def field(name: str) -> str:
            m = re.search(name + r":\s*'((?:\\.|[^'\\])*)'", record)
            return js_string(m.group(1)) if m else ""
        topic = {
            "id": int(re.match(r"id:\s*(\d+)", record).group(1)),
            "slug": field("slug"),
            "category": field("cat"),
            "categoryLabel": labels.get(field("cat"), ""),
            "title": field("title"),
            "date": field("date"),
            "author": field("author"),
            "lead": field("lead"),
            "excerpt": field("excerpt"),
            "blocks": [],
        }
        if "bodyHTML:" in record:
            html_part = record.split("bodyHTML:", 1)[1]
            pieces = re.findall(r"'((?:\\.|[^'\\])*)'", html_part.split("\n  }")[0])
            blocks, _ = html_to_blocks("".join(js_string(p) for p in pieces))
            topic["blocks"] = blocks
        topics.append(topic)
    return topics


# --------------------------------------------------------------------------
# 画像のコピー
# --------------------------------------------------------------------------
def copy_image(repo: Path, src: str) -> str | None:
    """RE_VAMOS 内の画像を縮小して assets にコピーし、アセットのパスを返す。"""
    path = repo / src
    if not path.is_file():
        return None
    kind = "avatar" if "/avatar/" in src else "hero" if "/hero/" in src else "body"
    name = re.sub(r"[^A-Za-z0-9._-]", "_", path.name)
    dest = OUT_DIR / "images" / kind / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        shutil.copyfile(path, dest)
        if dest.suffix.lower() in (".jpg", ".jpeg", ".png"):
            subprocess.run(["sips", "-Z", str(MAX_SIZE[kind]), str(dest)],
                           check=False, capture_output=True)
    return f"assets/vamos/images/{kind}/{name}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path, help="RE_VAMOS のクローン（main ブランチ）")
    parser.add_argument("--count", type=int, default=10, help="取り込むインタビューの本数")
    args = parser.parse_args()
    repo: Path = args.repo.resolve()

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    (OUT_DIR / "data").mkdir(parents=True)

    interviews = []
    for meta in sorted(load_interviews(repo), key=lambda m: m["date"], reverse=True):
        body_path = repo / meta.get("bodyUrl", "")
        if not body_path.is_file():
            continue
        blocks, _ = html_to_blocks(body_path.read_text(encoding="utf-8"))
        for block in blocks:
            for key in ("src", "avatar"):
                if block.get(key):
                    block[key] = copy_image(repo, block[key])
        blocks = [b for b in blocks if not (b["type"] == "image" and not b.get("src"))]
        interviews.append({
            "slug": meta["slug"],
            "title": meta["title"],
            "date": meta["date"],
            "readMinutes": meta.get("readMin") or 0,
            "thumbnail": copy_image(repo, meta.get("thumb", "")),
            "excerpt": meta.get("excerpt", ""),
            "author": meta.get("authorName") or "Vamos編集部",
            "company": (meta.get("company") or {}).get("name", ""),
            "blocks": blocks,
        })
        if len(interviews) >= args.count:
            break

    topics = load_topics(repo)

    logo = repo / "images" / "logo.png"
    if logo.is_file():
        shutil.copyfile(logo, OUT_DIR / "images" / "logo.png")

    (OUT_DIR / "data" / "interviews.json").write_text(
        json.dumps(interviews, ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT_DIR / "data" / "topics.json").write_text(
        json.dumps(topics, ensure_ascii=False, indent=1), encoding="utf-8")

    speech = sum(1 for i in interviews for b in i["blocks"] if b["type"] == "speech")
    print(f"interviews: {len(interviews)} (speech blocks: {speech}), topics: {len(topics)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
