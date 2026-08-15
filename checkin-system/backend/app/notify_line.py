"""ส่งข้อความแจ้งเตือนเข้ากลุ่ม LINE ผ่าน Messaging API

หมายเหตุสำคัญ: LINE Notify ปิดบริการไปแล้ว (1 เม.ย. 2025)
ตอนนี้ต้องใช้ Messaging API = สร้าง LINE Official Account แล้วเชิญบอทเข้ากลุ่ม
วิธีตั้งค่าทีละขั้น ดูที่ deploy/line/LINE_SETUP.md

หลักการของไฟล์นี้: **ห้ามทำให้ระบบเช็คอินล่ม**
ถ้าส่ง LINE ไม่ได้ (เน็ตล่ม / token หมดอายุ / โควตาหมด) ให้เขียน log แล้วผ่านไป
พนักงานต้องเช็คอินได้เสมอแม้ LINE จะใช้ไม่ได้
"""

import hashlib
import hmac
import json
import logging
import urllib.error
import urllib.request

from .config import settings

log = logging.getLogger("line")

PUSH_URL = "https://api.line.me/v2/bot/message/push"
REPLY_URL = "https://api.line.me/v2/bot/message/reply"


def is_configured() -> bool:
    """ตั้งค่าครบพร้อมส่งหรือยัง"""
    return bool(
        settings.line_notify_enabled
        and settings.line_channel_access_token.strip()
        and settings.line_target_id.strip()
    )


def _post(url: str, payload: dict) -> bool:
    token = settings.line_channel_access_token.strip()
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return 200 <= resp.status < 300
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")[:300]
        except Exception:
            pass
        log.warning("ส่ง LINE ไม่สำเร็จ (HTTP %s): %s", e.code, body)
    except Exception as e:  # เน็ตล่ม / timeout / DNS
        log.warning("ส่ง LINE ไม่สำเร็จ: %s", e)
    return False


def push_text(text: str, to: str | None = None) -> bool:
    """ส่งข้อความเข้ากลุ่ม/ห้องที่ตั้งไว้ คืน True ถ้าสำเร็จ

    ไม่เคย raise — ผู้เรียกไม่ต้องดักก็ได้
    """
    if not is_configured():
        log.debug("ยังไม่ได้ตั้งค่า LINE — ข้ามการแจ้งเตือน")
        return False

    target = (to or settings.line_target_id).strip()
    # LINE จำกัดข้อความละ 5,000 ตัวอักษร ตัดกันพลาด
    text = text[:4900]
    return _post(PUSH_URL, {"to": target, "messages": [{"type": "text", "text": text}]})


def reply_text(reply_token: str, text: str) -> bool:
    """ตอบกลับข้อความใน chat (ใช้ตอนบอทบอก Group ID ของตัวเอง)"""
    if not settings.line_channel_access_token.strip():
        return False
    return _post(
        REPLY_URL,
        {"replyToken": reply_token, "messages": [{"type": "text", "text": text[:4900]}]},
    )


def verify_signature(body: bytes, signature: str | None) -> bool:
    """ตรวจว่า webhook มาจาก LINE จริง (ป้องกันคนอื่นยิงมั่ว)

    ถ้ายังไม่ได้ตั้ง channel secret จะคืน False = ปฏิเสธไว้ก่อน ปลอดภัยกว่า
    """
    secret = settings.line_channel_secret.strip()
    if not secret or not signature:
        return False
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).digest()
    import base64

    expected = base64.b64encode(digest).decode("utf-8")
    return hmac.compare_digest(expected, signature)
