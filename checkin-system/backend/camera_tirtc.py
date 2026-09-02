"""ออก connection token สำหรับ Tange TiRTC โดยไม่พึ่งไลบรารีภายนอก

รูปแบบ token อ้างอิงเอกสารทางการของ Tange:

    v1.<base64url(payload)>.<base64url(HMAC-SHA256(secret, payload_b64))>

ไฟล์นี้แยกจาก FastAPI เพื่อให้ทดสอบลายเซ็นได้โดยไม่ต้องต่อฐานข้อมูลหรือกล้อง
จริง และที่สำคัญ SecretKeyId จะอยู่เฉพาะฝั่งเซิร์ฟเวอร์เท่านั้น
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class TiRtcConnectToken:
    value: str
    issued_at: int
    expires_at: int


def _base64url(data: bytes) -> str:
    """base64url แบบไม่มี padding ตามสัญญา token ของ TiRTC"""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_connect_token(
    *,
    access_key_id: str,
    secret_key_id: str,
    remote_id: str,
    subject: str,
    ttl_seconds: int,
    now: int | None = None,
    nonce: str | None = None,
) -> TiRtcConnectToken:
    """สร้าง token หนึ่งครั้งสำหรับเชื่อม client ไปยังกล้องหนึ่งตัว

    ``now`` และ ``nonce`` เปิดให้ส่งค่าแน่นอนได้เฉพาะเพื่อทดสอบ ผลใช้งานจริง
    จะใช้เวลาปัจจุบันและ nonce แบบ cryptographically secure ทุกคำขอ
    """
    values = {
        "access_key_id": access_key_id,
        "secret_key_id": secret_key_id,
        "remote_id": remote_id,
        "subject": subject,
    }
    missing = [name for name, value in values.items() if not value.strip()]
    if missing:
        raise ValueError(f"TiRTC token fields must not be empty: {', '.join(missing)}")
    if ttl_seconds <= 0:
        raise ValueError("ttl_seconds must be greater than zero")

    issued_at = int(time.time()) if now is None else int(now)
    expires_at = issued_at + int(ttl_seconds)
    token_nonce = nonce or secrets.token_urlsafe(16)

    payload = {
        "sub": subject,
        "scope": f"connect:device://{remote_id}",
        "iss": access_key_id,
        "iat": issued_at,
        "exp": expires_at,
        "nonce": token_nonce,
    }
    payload_json = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    payload_b64 = _base64url(payload_json)
    signature = hmac.new(
        secret_key_id.encode("utf-8"),
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).digest()

    return TiRtcConnectToken(
        value=f"v1.{payload_b64}.{_base64url(signature)}",
        issued_at=issued_at,
        expires_at=expires_at,
    )
