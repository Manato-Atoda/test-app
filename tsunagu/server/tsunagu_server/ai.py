"""AI インサイト（管理者向けの定性レポート）。

社内のやり取りの集計値と、氏名を外した投稿の抜粋を Claude（Anthropic の API）に渡し、
「いま組織で何が起きているか」を日本語のレポートにする。管理者がボタンを押したときだけ動く。

使うには（運営者がサーバー側で設定）:
  - Python 3.10 以上で `pip install anthropic`（公式 SDK。サーバー本体は標準ライブラリだけで動く）
  - 環境変数 TSUNAGU_AI_PROVIDER=anthropic と ANTHROPIC_API_KEY
    （ANTHROPIC_API_KEY がなくても、`ant auth login` 済みなら SDK がその認証情報を使う）
  - 動作確認用に TSUNAGU_AI_PROVIDER=mock にすると、外部に送らずにテスト用の仮レポートを作る

外部に送るのは集計値と投稿の抜粋（氏名・社員コード・メールアドレスは含めない）だけ。
"""
from __future__ import annotations

import os
from typing import Any, Dict, Tuple

MODEL = "claude-opus-5-5"
MAX_TOKENS = 16000

SYSTEM_PROMPT = """あなたは日本企業の組織開発・社内コミュニケーションの専門家です。
社内 SNS の利用状況の集計と、投稿の抜粋（個人名は伏せてあります）を読み、人事・経営層の管理者に向けて
「いま組織で何が起きているか」を日本語のレポートにまとめてください。

- Markdown で、見出し（##）と箇条書きを使い、全体で 1,500 字程度に収めてください。
- 構成: ## 全体の様子 / ## 目立つ動き / ## 気にかけたい点 / ## 次の一手（具体的な提案を 3 つまで）
- 数字は集計に書かれているものだけを使い、推測で数字を作らないでください。
- 特定の個人を評価・特定するような書き方はしないでください（部署・チャンネル単位で述べる）。
- データが少ない場合は、少ないことを前置きしたうえで言える範囲で書いてください。"""


def status() -> Dict[str, Any]:
    provider = (os.environ.get("TSUNAGU_AI_PROVIDER") or "").strip().lower()
    if provider == "mock":
        return {"configured": True, "provider": "mock", "model": "mock",
                "message": "テスト用の仮レポートを作る設定です（外部には送りません）"}
    if provider != "anthropic":
        return {"configured": False, "provider": None, "model": MODEL,
                "message": "サーバーの環境変数 TSUNAGU_AI_PROVIDER=anthropic と ANTHROPIC_API_KEY を設定すると使えます"}
    try:
        import anthropic  # noqa: F401  # 任意の依存（Python 3.10 以上）
    except ImportError:
        return {"configured": False, "provider": "anthropic", "model": MODEL,
                "message": "サーバーに Anthropic の公式 SDK がありません（Python 3.10 以上で pip install anthropic）"}
    return {"configured": True, "provider": "anthropic", "model": MODEL,
            "message": "Claude（%s）で作成します。集計値と氏名を伏せた投稿の抜粋を Anthropic の API に送ります" % MODEL}


class AIError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


def generate(digest: str) -> Tuple[str, str, Dict[str, int]]:
    """(Markdown の本文, 使ったモデル, トークン数) を返す。"""
    st = status()
    if not st["configured"]:
        raise AIError(st["message"])
    if st["provider"] == "mock":
        return _mock_report(digest), "mock", {"input_tokens": 0, "output_tokens": 0}

    import anthropic

    client = anthropic.Anthropic()  # 認証情報は環境（ANTHROPIC_API_KEY など）から
    try:
        response = client.beta.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            output_config={"effort": "high"},
            # 安全上の理由で断られたときは、サーバー側で別のモデルに引き継ぐ
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": digest}],
        )
    except anthropic.AuthenticationError:
        raise AIError("Anthropic の API キーが正しくありません（サーバーの設定を確認してください）")
    except anthropic.PermissionDeniedError:
        raise AIError("この API キーではこのモデルを使えません")
    except anthropic.RateLimitError:
        raise AIError("AI の利用回数の上限に達しました。しばらく待ってからやり直してください")
    except anthropic.BadRequestError as exc:
        raise AIError("AI へのリクエストが受け付けられませんでした（%s）" % exc.message)
    except anthropic.APIStatusError as exc:
        raise AIError("AI のサービスでエラーが発生しました（%s）。時間をおいてやり直してください" % exc.status_code)
    except anthropic.APIConnectionError:
        raise AIError("AI のサービスに接続できませんでした。ネットワークを確認してください")

    if response.stop_reason == "refusal":
        raise AIError("AI がこの内容のレポート作成を断りました。集計の対象や期間を変えてお試しください")
    text = "\n".join(block.text for block in response.content if block.type == "text").strip()
    if not text:
        raise AIError("AI から本文が返ってきませんでした。もう一度お試しください")
    if response.stop_reason == "max_tokens":
        text += "\n\n（文字数の上限に達したため、ここで途切れています）"
    usage = {"input_tokens": response.usage.input_tokens, "output_tokens": response.usage.output_tokens}
    return text, response.model, usage


def _mock_report(digest: str) -> str:
    lines = [line for line in digest.splitlines() if line.startswith("- ")][:6]
    return ("> これは動作確認用の**仮レポート**です（AI は使っていません）。\n\n"
            "## 全体の様子\n" + "\n".join(lines or ["- データがまだ少ない状態です"]) + "\n\n"
            "## 目立つ動き\n- 集計の抜粋をそのまま表示しています\n\n"
            "## 気にかけたい点\n- 本番では Claude が集計を読み、気になる点を文章でまとめます\n\n"
            "## 次の一手\n- サーバーに TSUNAGU_AI_PROVIDER=anthropic と API キーを設定してください\n")
