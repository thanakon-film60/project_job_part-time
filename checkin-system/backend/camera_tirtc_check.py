r"""ตรวจรูปแบบและความปลอดภัยพื้นฐานของ TiRTC connection token

รันด้วย:
    venv\Scripts\python.exe camera_tirtc_check.py

ไม่ต้องต่อฐานข้อมูล อินเทอร์เน็ต หรือกล้องจริง
"""

import base64
import hashlib
import hmac
import json
import sys

from camera_tirtc import generate_connect_token


def _decode_base64url(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def check_contract() -> str:
    issued = generate_connect_token(
        access_key_id="test-access",
        secret_key_id="test-secret",
        remote_id="camera-001",
        subject="employee:BOSS001",
        ttl_seconds=120,
        now=1_700_000_000,
        nonce="fixed-nonce",
    )
    version, payload_b64, signature_b64 = issued.value.split(".")
    assert version == "v1"
    assert "=" not in payload_b64 and "=" not in signature_b64

    payload = json.loads(_decode_base64url(payload_b64))
    assert payload == {
        "sub": "employee:BOSS001",
        "scope": "connect:device://camera-001",
        "iss": "test-access",
        "iat": 1_700_000_000,
        "exp": 1_700_000_120,
        "nonce": "fixed-nonce",
    }
    assert issued.issued_at == payload["iat"]
    assert issued.expires_at == payload["exp"]

    expected = hmac.new(
        b"test-secret",
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).digest()
    assert hmac.compare_digest(_decode_base64url(signature_b64), expected)
    return "รูปแบบ claims, TTL และ HMAC-SHA256 ถูกต้อง"


def check_nonce_changes() -> str:
    values = {
        generate_connect_token(
            access_key_id="access",
            secret_key_id="secret",
            remote_id="camera-001",
            subject="employee:BOSS001",
            ttl_seconds=60,
            now=1_700_000_000,
        ).value
        for _ in range(8)
    }
    assert len(values) == 8, "ทุกคำขอต้องได้ nonce/token คนละค่า"
    return "ออก token 8 ครั้งได้ค่าไม่ซ้ำกัน"


def check_rejects_incomplete_input() -> str:
    try:
        generate_connect_token(
            access_key_id="",
            secret_key_id="secret",
            remote_id="camera-001",
            subject="employee:BOSS001",
            ttl_seconds=60,
        )
    except ValueError as exc:
        assert "access_key_id" in str(exc)
    else:
        raise AssertionError("ต้องปฏิเสธ credential ที่ไม่ครบ")
    return "ปฏิเสธ credential ว่างก่อนออก token"


CHECKS = [
    ("สัญญา token", check_contract),
    ("nonce ไม่ซ้ำ", check_nonce_changes),
    ("credential ต้องครบ", check_rejects_incomplete_input),
]


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    failures = 0
    for index, (label, check) in enumerate(CHECKS, start=1):
        try:
            detail = check()
        except AssertionError as exc:
            failures += 1
            print(f"{index}. {label}: ไม่ผ่าน — {exc}")
        else:
            print(f"{index}. {label}: ผ่าน — {detail}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
