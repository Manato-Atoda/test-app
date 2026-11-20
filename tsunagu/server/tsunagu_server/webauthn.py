"""パスキー（WebAuthn）の検証。

外部ライブラリなしで動くように、必要な部分（CBOR・COSE 鍵・ES256 / RS256 の署名検証）だけを実装している。
本番運用では、監査済みのライブラリ（py_webauthn + cryptography など）への置き換えを推奨。

- 登録: attestation は "none" を要求し、構成証明（端末メーカーの証明書）は検証しない。
- 認証: rpIdHash・origin・challenge・UP/UV フラグ・署名・署名カウンタを検証する。
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import struct
from typing import Any, Dict, List, Optional, Tuple

ALG_ES256 = -7
ALG_RS256 = -257
SUPPORTED_ALGS = (ALG_ES256, ALG_RS256)

FLAG_UP = 0x01
FLAG_UV = 0x04
FLAG_BE = 0x08
FLAG_BS = 0x10
FLAG_AT = 0x40


class WebAuthnError(Exception):
    """検証に失敗したときの例外。メッセージは利用者に見せない（ログ用）。"""


# ---------------------------------------------------------------- base64url

def b64u_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64u_decode(value: Any) -> bytes:
    if not isinstance(value, str) or len(value) > 65536:
        raise WebAuthnError("base64url の形式が不正です")
    value = value.strip().replace("+", "-").replace("/", "_").rstrip("=")
    try:
        return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except (ValueError, TypeError) as exc:
        raise WebAuthnError("base64url の形式が不正です") from exc


# ---------------------------------------------------------------- CBOR (RFC 8949)

_MAX_ITEMS = 4096


def cbor_decode(data: bytes, offset: int = 0, _depth: int = 0) -> Tuple[Any, int]:
    """data[offset:] から CBOR を 1 つ読み、(値, 次の位置) を返す。"""
    if _depth > 16:
        raise WebAuthnError("CBOR: 入れ子が深すぎます")
    if offset >= len(data):
        raise WebAuthnError("CBOR: データが途中で終わっています")
    initial = data[offset]
    offset += 1
    major, info = initial >> 5, initial & 0x1F

    if major == 7:
        if info == 20:
            return False, offset
        if info == 21:
            return True, offset
        if info in (22, 23):
            return None, offset
        if info == 25:
            return _read_float(data, offset, 2, ">e")
        if info == 26:
            return _read_float(data, offset, 4, ">f")
        if info == 27:
            return _read_float(data, offset, 8, ">d")
        raise WebAuthnError("CBOR: 未対応の simple value")

    if info < 24:
        arg = info
    elif info in (24, 25, 26, 27):
        size = 1 << (info - 24)
        if offset + size > len(data):
            raise WebAuthnError("CBOR: データが途中で終わっています")
        arg = int.from_bytes(data[offset:offset + size], "big")
        offset += size
    else:
        raise WebAuthnError("CBOR: 不定長は未対応です")

    if major == 0:
        return arg, offset
    if major == 1:
        return -1 - arg, offset
    if major in (2, 3):
        end = offset + arg
        if end > len(data):
            raise WebAuthnError("CBOR: データが途中で終わっています")
        raw = data[offset:end]
        if major == 2:
            return bytes(raw), end
        try:
            return raw.decode("utf-8"), end
        except UnicodeDecodeError as exc:
            raise WebAuthnError("CBOR: 文字列が UTF-8 ではありません") from exc
    if major == 4:
        if arg > _MAX_ITEMS:
            raise WebAuthnError("CBOR: 配列が大きすぎます")
        items = []
        for _ in range(arg):
            value, offset = cbor_decode(data, offset, _depth + 1)
            items.append(value)
        return items, offset
    if major == 5:
        if arg > _MAX_ITEMS:
            raise WebAuthnError("CBOR: マップが大きすぎます")
        result: Dict[Any, Any] = {}
        for _ in range(arg):
            key, offset = cbor_decode(data, offset, _depth + 1)
            if isinstance(key, (list, dict)):
                raise WebAuthnError("CBOR: 不正なキー")
            value, offset = cbor_decode(data, offset, _depth + 1)
            result[key] = value
        return result, offset
    # major == 6: タグは中身だけ使う
    return cbor_decode(data, offset, _depth + 1)


def _read_float(data: bytes, offset: int, size: int, fmt: str) -> Tuple[float, int]:
    if offset + size > len(data):
        raise WebAuthnError("CBOR: データが途中で終わっています")
    return struct.unpack(fmt, data[offset:offset + size])[0], offset + size


def cbor_encode(value: Any) -> bytes:
    """テストと COSE 鍵の組み立て用の最小限のエンコーダ。"""
    def head(major: int, arg: int) -> bytes:
        if arg < 24:
            return bytes([(major << 5) | arg])
        for info, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
            if arg < (1 << (8 * size)):
                return bytes([(major << 5) | info]) + arg.to_bytes(size, "big")
        raise ValueError("too large")

    if value is False:
        return b"\xf4"
    if value is True:
        return b"\xf5"
    if value is None:
        return b"\xf6"
    if isinstance(value, int):
        return head(0, value) if value >= 0 else head(1, -1 - value)
    if isinstance(value, bytes):
        return head(2, len(value)) + value
    if isinstance(value, str):
        raw = value.encode("utf-8")
        return head(3, len(raw)) + raw
    if isinstance(value, (list, tuple)):
        return head(4, len(value)) + b"".join(cbor_encode(v) for v in value)
    if isinstance(value, dict):
        return head(5, len(value)) + b"".join(cbor_encode(k) + cbor_encode(v) for k, v in value.items())
    raise TypeError("unsupported type: %r" % type(value))


# ---------------------------------------------------------------- P-256 (secp256r1)

P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
G = (0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
     0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5)

_INF = (0, 1, 0)  # ヤコビアン座標の無限遠点


def _on_curve(x: int, y: int) -> bool:
    return 0 <= x < P and 0 <= y < P and (y * y - (x * x * x - 3 * x + B)) % P == 0


def _jdouble(pt: Tuple[int, int, int]) -> Tuple[int, int, int]:
    x1, y1, z1 = pt
    if z1 == 0 or y1 == 0:
        return _INF
    delta = z1 * z1 % P
    gamma = y1 * y1 % P
    beta = x1 * gamma % P
    alpha = 3 * (x1 - delta) * (x1 + delta) % P
    x3 = (alpha * alpha - 8 * beta) % P
    z3 = ((y1 + z1) * (y1 + z1) - gamma - delta) % P
    y3 = (alpha * (4 * beta - x3) - 8 * gamma * gamma) % P
    return x3, y3, z3


def _jadd(p1: Tuple[int, int, int], p2: Tuple[int, int, int]) -> Tuple[int, int, int]:
    x1, y1, z1 = p1
    x2, y2, z2 = p2
    if z1 == 0:
        return p2
    if z2 == 0:
        return p1
    z1z1 = z1 * z1 % P
    z2z2 = z2 * z2 % P
    u1 = x1 * z2z2 % P
    u2 = x2 * z1z1 % P
    s1 = y1 * z2 * z2z2 % P
    s2 = y2 * z1 * z1z1 % P
    if u1 == u2:
        return _jdouble(p1) if s1 == s2 else _INF
    h = (u2 - u1) % P
    i = (2 * h) * (2 * h) % P
    j = h * i % P
    r = 2 * (s2 - s1) % P
    v = u1 * i % P
    x3 = (r * r - j - 2 * v) % P
    y3 = (r * (v - x3) - 2 * s1 * j) % P
    z3 = ((z1 + z2) * (z1 + z2) - z1z1 - z2z2) * h % P
    return x3, y3, z3


def _jmul(k: int, point: Tuple[int, int]) -> Tuple[int, int, int]:
    result = _INF
    addend = (point[0], point[1], 1)
    while k:
        if k & 1:
            result = _jadd(result, addend)
        addend = _jdouble(addend)
        k >>= 1
    return result


def _to_affine(pt: Tuple[int, int, int]) -> Optional[Tuple[int, int]]:
    x, y, z = pt
    if z == 0:
        return None
    zinv = pow(z, -1, P)
    zinv2 = zinv * zinv % P
    return x * zinv2 % P, y * zinv2 * zinv % P


def p256_public_key(private_key: int) -> Tuple[int, int]:
    """テスト用（疑似認証器）。"""
    point = _to_affine(_jmul(private_key, G))
    assert point is not None
    return point


def p256_sign(private_key: int, message: bytes, nonce: int) -> bytes:
    """テスト用（疑似認証器）。DER 形式の署名を返す。"""
    e = int.from_bytes(hashlib.sha256(message).digest(), "big")
    r_point = _to_affine(_jmul(nonce, G))
    assert r_point is not None
    r = r_point[0] % N
    s = pow(nonce, -1, N) * (e + r * private_key) % N
    return _der_encode_sig(r, s)


def _der_int(value: int) -> bytes:
    raw = value.to_bytes((value.bit_length() + 8) // 8 or 1, "big")
    return b"\x02" + bytes([len(raw)]) + raw


def _der_encode_sig(r: int, s: int) -> bytes:
    body = _der_int(r) + _der_int(s)
    return b"\x30" + bytes([len(body)]) + body


def _der_decode_sig(sig: bytes) -> Tuple[int, int]:
    def read_int(buf: bytes, pos: int) -> Tuple[int, int]:
        if pos + 2 > len(buf) or buf[pos] != 0x02:
            raise WebAuthnError("署名の形式が不正です")
        length = buf[pos + 1]
        start, end = pos + 2, pos + 2 + length
        if length == 0 or length > 33 or end > len(buf):
            raise WebAuthnError("署名の形式が不正です")
        return int.from_bytes(buf[start:end], "big"), end

    if len(sig) < 8 or sig[0] != 0x30 or sig[1] != len(sig) - 2:
        raise WebAuthnError("署名の形式が不正です")
    r, pos = read_int(sig, 2)
    s, pos = read_int(sig, pos)
    if pos != len(sig):
        raise WebAuthnError("署名の形式が不正です")
    return r, s


def verify_es256(x: int, y: int, message: bytes, signature: bytes) -> bool:
    if not _on_curve(x, y):
        return False
    try:
        r, s = _der_decode_sig(signature)
    except WebAuthnError:
        return False
    if not (1 <= r < N and 1 <= s < N):
        return False
    e = int.from_bytes(hashlib.sha256(message).digest(), "big")
    w = pow(s, -1, N)
    point = _to_affine(_jadd(_jmul(e * w % N, G), _jmul(r * w % N, (x, y))))
    return point is not None and point[0] % N == r


_SHA256_DIGEST_INFO = bytes.fromhex("3031300d060960864801650304020105000420")


def verify_rs256(n: int, e: int, message: bytes, signature: bytes) -> bool:
    k = (n.bit_length() + 7) // 8
    if n.bit_length() < 2048 or len(signature) != k:
        return False
    s = int.from_bytes(signature, "big")
    if s >= n:
        return False
    em = pow(s, e, n).to_bytes(k, "big")
    t = _SHA256_DIGEST_INFO + hashlib.sha256(message).digest()
    if k < len(t) + 11:
        return False
    expected = b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    return hmac.compare_digest(em, expected)


# ---------------------------------------------------------------- COSE 鍵

def parse_cose_key(cose: bytes) -> Dict[str, Any]:
    key, end = cbor_decode(cose)
    if end != len(cose) or not isinstance(key, dict):
        raise WebAuthnError("公開鍵の形式が不正です")
    kty, alg = key.get(1), key.get(3)
    if kty == 2 and alg == ALG_ES256:
        x, y = key.get(-2), key.get(-3)
        if key.get(-1) != 1 or not isinstance(x, bytes) or not isinstance(y, bytes) \
                or len(x) != 32 or len(y) != 32:
            raise WebAuthnError("P-256 公開鍵が不正です")
        xi, yi = int.from_bytes(x, "big"), int.from_bytes(y, "big")
        if not _on_curve(xi, yi):
            raise WebAuthnError("公開鍵が曲線上にありません")
        return {"alg": ALG_ES256, "x": xi, "y": yi}
    if kty == 3 and alg == ALG_RS256:
        n, e = key.get(-1), key.get(-2)
        if not isinstance(n, bytes) or not isinstance(e, bytes):
            raise WebAuthnError("RSA 公開鍵が不正です")
        return {"alg": ALG_RS256, "n": int.from_bytes(n, "big"), "e": int.from_bytes(e, "big")}
    raise WebAuthnError("未対応の鍵の種類です (kty=%r, alg=%r)" % (kty, alg))


def verify_signature(cose: bytes, message: bytes, signature: bytes) -> bool:
    key = parse_cose_key(cose)
    if key["alg"] == ALG_ES256:
        return verify_es256(key["x"], key["y"], message, signature)
    return verify_rs256(key["n"], key["e"], message, signature)


# ---------------------------------------------------------------- authenticatorData

def parse_authenticator_data(data: bytes) -> Dict[str, Any]:
    if len(data) < 37:
        raise WebAuthnError("authenticatorData が短すぎます")
    flags = data[32]
    parsed: Dict[str, Any] = {
        "rp_id_hash": data[:32],
        "flags": flags,
        "sign_count": struct.unpack(">I", data[33:37])[0],
    }
    if flags & FLAG_AT:
        if len(data) < 55:
            raise WebAuthnError("attestedCredentialData が短すぎます")
        cred_len = int.from_bytes(data[53:55], "big")
        cred_end = 55 + cred_len
        if cred_len == 0 or cred_len > 1023 or cred_end > len(data):
            raise WebAuthnError("credentialId が不正です")
        _, key_end = cbor_decode(data, cred_end)
        parsed["aaguid"] = data[37:53].hex()
        parsed["credential_id"] = data[55:cred_end]
        parsed["public_key"] = data[cred_end:key_end]
    return parsed


def _check_client_data(raw: bytes, *, expected_type: str, challenge: bytes,
                       origins: List[str]) -> None:
    try:
        client_data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise WebAuthnError("clientDataJSON が不正です") from exc
    if not isinstance(client_data, dict) or client_data.get("type") != expected_type:
        raise WebAuthnError("clientData.type が違います")
    if not hmac.compare_digest(b64u_decode(client_data.get("challenge")), challenge):
        raise WebAuthnError("challenge が一致しません")
    if client_data.get("origin") not in origins:
        raise WebAuthnError("origin が許可されていません: %r" % client_data.get("origin"))
    if client_data.get("crossOrigin") is True:
        raise WebAuthnError("crossOrigin は許可していません")


def _check_flags(parsed: Dict[str, Any], rp_id: str, require_uv: bool) -> None:
    if not hmac.compare_digest(parsed["rp_id_hash"], hashlib.sha256(rp_id.encode("utf-8")).digest()):
        raise WebAuthnError("rpIdHash が一致しません")
    if not parsed["flags"] & FLAG_UP:
        raise WebAuthnError("ユーザーの操作（UP）がありません")
    if require_uv and not parsed["flags"] & FLAG_UV:
        raise WebAuthnError("本人確認（UV）がありません")


def _response(credential: Any) -> Dict[str, Any]:
    if not isinstance(credential, dict) or credential.get("type") != "public-key":
        raise WebAuthnError("credential の形式が不正です")
    response = credential.get("response")
    if not isinstance(response, dict):
        raise WebAuthnError("credential.response がありません")
    return response


def verify_registration(credential: Any, *, challenge: bytes, origins: List[str], rp_id: str,
                        require_uv: bool = True) -> Dict[str, Any]:
    response = _response(credential)
    _check_client_data(b64u_decode(response.get("clientDataJSON")),
                       expected_type="webauthn.create", challenge=challenge, origins=origins)
    attestation, end = cbor_decode(b64u_decode(response.get("attestationObject")))
    if not isinstance(attestation, dict) or not isinstance(attestation.get("authData"), bytes):
        raise WebAuthnError("attestationObject が不正です")
    parsed = parse_authenticator_data(attestation["authData"])
    _check_flags(parsed, rp_id, require_uv)
    if "credential_id" not in parsed:
        raise WebAuthnError("認証器の鍵情報がありません")
    raw_id = b64u_decode(credential.get("rawId") or credential.get("id"))
    if not hmac.compare_digest(raw_id, parsed["credential_id"]):
        raise WebAuthnError("credentialId が一致しません")
    key = parse_cose_key(parsed["public_key"])
    transports = response.get("transports")
    if not isinstance(transports, list):
        transports = []
    return {
        "credential_id": b64u_encode(parsed["credential_id"]),
        "public_key": parsed["public_key"],
        "alg": key["alg"],
        "sign_count": parsed["sign_count"],
        "aaguid": parsed["aaguid"],
        "backed_up": bool(parsed["flags"] & FLAG_BS),
        "transports": [t for t in transports if isinstance(t, str)][:8],
    }


def verify_authentication(credential: Any, *, challenge: bytes, origins: List[str], rp_id: str,
                          public_key: bytes, stored_sign_count: int,
                          require_uv: bool = True) -> int:
    """検証に成功したら新しい署名カウンタを返す。"""
    response = _response(credential)
    client_data_raw = b64u_decode(response.get("clientDataJSON"))
    _check_client_data(client_data_raw, expected_type="webauthn.get", challenge=challenge,
                       origins=origins)
    auth_data = b64u_decode(response.get("authenticatorData"))
    parsed = parse_authenticator_data(auth_data)
    _check_flags(parsed, rp_id, require_uv)
    signature = b64u_decode(response.get("signature"))
    signed = auth_data + hashlib.sha256(client_data_raw).digest()
    if not verify_signature(public_key, signed, signature):
        raise WebAuthnError("署名が正しくありません")
    new_count = parsed["sign_count"]
    if (new_count or stored_sign_count) and new_count <= stored_sign_count:
        raise WebAuthnError("署名カウンタが戻っています（認証器の複製の疑い）")
    return new_count
