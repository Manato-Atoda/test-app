"""パスワードのハッシュ化・規則チェック・仮パスワードの生成。"""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import string
from typing import Any, Dict, Iterable, List, Optional

# OWASP Password Storage Cheat Sheet（PBKDF2-HMAC-SHA256: 600,000 回）
DEFAULT_ITERATIONS = 600_000
ITERATIONS = int(os.environ.get("TSUNAGU_PBKDF2_ITERATIONS", DEFAULT_ITERATIONS))

SYMBOLS = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
MAX_LENGTH = 128
HISTORY_SIZE = 5

# よく使われる弱いパスワード（英字＋数字の規則を満たしてしまうもの）
_COMMON = {
    "password1", "password12", "password123", "passw0rd", "p@ssw0rd", "abc12345", "abcd1234",
    "qwerty123", "qwerty12", "a1234567", "1234567a", "12345678a", "1qaz2wsx", "zaq12wsx",
    "admin123", "welcome1", "iloveyou1", "letmein1", "test1234", "pass1234", "company1",
}


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS)
    return "pbkdf2_sha256$%d$%s$%s" % (
        ITERATIONS,
        base64.b64encode(salt).decode("ascii"),
        base64.b64encode(digest).decode("ascii"),
    )


def verify_password(password: str, encoded: Optional[str]) -> bool:
    if not encoded:
        # 利用者がいない・未発行でも処理時間をそろえる
        hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), b"tsunagu-dummy-salt", ITERATIONS)
        return False
    try:
        algorithm, iterations, salt, digest = encoded.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"),
                                     base64.b64decode(salt), int(iterations))
        return hmac.compare_digest(actual, base64.b64decode(digest))
    except (ValueError, TypeError):
        return False


def policy_from_settings(settings: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "min_length": max(8, int(settings.get("password_min_length", 8))),
        "max_length": MAX_LENGTH,
        "require_letter": True,
        "require_digit": True,
        "require_symbol": bool(settings.get("password_require_symbol", False)),
        "allowed_symbols": SYMBOLS,
    }


def check_policy(password: str, policy: Dict[str, Any], *, employee_code: str = "",
                 email: Optional[str] = None) -> List[str]:
    """規則に合わない点を日本語で返す（空なら合格）。"""
    problems: List[str] = []
    if len(password) < policy["min_length"]:
        problems.append("%d文字以上にしてください" % policy["min_length"])
    if len(password) > policy["max_length"]:
        problems.append("%d文字以内にしてください" % policy["max_length"])
    allowed = set(string.ascii_letters + string.digits + SYMBOLS)
    if any(ch not in allowed for ch in password):
        problems.append("使えるのは半角の英字・数字・記号だけです（空白・全角は使えません）")
    if not any(ch in string.ascii_letters for ch in password):
        problems.append("英字を1文字以上含めてください")
    if not any(ch in string.digits for ch in password):
        problems.append("数字を1文字以上含めてください")
    if policy.get("require_symbol") and not any(ch in SYMBOLS for ch in password):
        problems.append("記号を1文字以上含めてください")
    lowered = password.lower()
    if employee_code and len(employee_code) >= 3 and employee_code.lower() in lowered:
        problems.append("社員コードを含めないでください")
    if email:
        local = email.split("@", 1)[0].lower()
        if len(local) >= 3 and local in lowered:
            problems.append("メールアドレスを含めないでください")
    if lowered in _COMMON:
        problems.append("推測されやすいパスワードです")
    return problems


def reused(password: str, hashes: Iterable[str]) -> bool:
    return any(verify_password(password, h) for h in hashes if h)


_TEMP_ALPHABET_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ"   # I, O を除く
_TEMP_ALPHABET_LOWER = "abcdefghijkmnpqrstuvwxyz"   # l, o を除く
_TEMP_DIGITS = "23456789"                           # 0, 1 を除く


def generate_temporary_password() -> str:
    """紙に印刷しても読み間違えにくい仮パスワード（例: Xk7m-Qp3r-Tn9w）。

    12 文字＋区切りのハイフン 2 つ。大文字・小文字・数字・記号をすべて含むので、
    企業設定で「記号必須」にしていても規則を満たす。
    """
    pool = _TEMP_ALPHABET_UPPER + _TEMP_ALPHABET_LOWER + _TEMP_DIGITS
    while True:
        chars = [secrets.choice(pool) for _ in range(12)]
        joined = "".join(chars)
        if (any(c in _TEMP_ALPHABET_UPPER for c in joined)
                and any(c in _TEMP_ALPHABET_LOWER for c in joined)
                and sum(c in _TEMP_DIGITS for c in joined) >= 2):
            return "%s-%s-%s" % (joined[0:4], joined[4:8], joined[8:12])
