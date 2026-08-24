"""Endpoint ฝั่ง LINE — webhook + เครื่องมือช่วยตั้งค่า

จุดประสงค์หลักของ webhook: **หา Group ID ให้อัตโนมัติ**
ปกติการหา Group ID เป็นขั้นตอนที่งงที่สุด — ที่นี่แค่พิมพ์ "id" ในกลุ่ม
แล้วบอทจะตอบ Group ID กลับมาในกลุ่มเลย เอาไปใส่ .env ได้ทันที
"""

import logging
import os

from fastapi import APIRouter, Depends, Header, Request

from ..config import settings
from ..models import Employee
from ..notify_line import is_configured, push_text, reply_text, verify_signature
from ..security import require_manager

router = APIRouter(prefix="/line", tags=["line"])
log = logging.getLogger("line")

# ScheduledTask has no visible console. Keep a small local audit log so LINE
# webhook failures can be diagnosed without recording tokens or secrets.
_log_dir = os.path.join(settings.storage_dir, "logs")
os.makedirs(_log_dir, exist_ok=True)
_audit_path = os.path.abspath(os.path.join(_log_dir, "line-webhook.log"))
if not any(
    isinstance(handler, logging.FileHandler)
    and os.path.abspath(handler.baseFilename) == _audit_path
    for handler in log.handlers
):
    _handler = logging.FileHandler(_audit_path, encoding="utf-8")
    _handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(_handler)
log.setLevel(logging.INFO)


@router.post("/webhook")
async def webhook(request: Request, x_line_signature: str | None = Header(None)):
    """LINE เรียกเข้ามาเมื่อมีเหตุการณ์ในแชต (เชิญบอทเข้ากลุ่ม / มีคนพิมพ์)

    ต้องตอบ 200 เสมอ ไม่งั้น LINE จะมองว่า endpoint เสียแล้วเลิกส่งมา
    """
    body = await request.body()

    if not verify_signature(body, x_line_signature):
        # ไม่ใช่ของจริง (หรือยังไม่ได้ตั้ง LINE_CHANNEL_SECRET)
        log.warning("webhook: ลายเซ็นไม่ถูกต้อง — ปฏิเสธ")
        return {"ok": False, "reason": "invalid signature"}

    try:
        payload = await request.json()
    except Exception:
        return {"ok": True}

    for event in payload.get("events", []):
        source = event.get("source", {}) or {}
        stype = source.get("type")
        sid = source.get("groupId") or source.get("roomId") or source.get("userId")
        etype = event.get("type")

        # เขียนลง log ด้วยเสมอ เผื่อ reply token หมดอายุ
        log.info("webhook event=%s source=%s id=%s", etype, stype, sid)

        # ถูกเชิญเข้ากลุ่ม -> ทักทายพร้อมบอก ID เลย
        if etype in ("join", "memberJoined"):
            reply_token = event.get("replyToken")
            if reply_token:
                reply_ok = reply_text(
                    reply_token,
                    "สวัสดีครับ ผมคือบอทแจ้งเตือนเข้างาน THANAKON-ROOM\n\n"
                    f"ID ของห้องนี้คือ:\n{sid}\n\n"
                    "เอาค่านี้ไปใส่ LINE_TARGET_ID ใน .env ของระบบ "
                    "แล้ว restart backend เป็นอันเสร็จ",
                )
                log.info("webhook join reply_ok=%s source=%s id=%s", reply_ok, stype, sid)
            continue

        # พิมพ์ "id" ในกลุ่ม -> ตอบ ID กลับ (เผื่อพลาดตอนบอทเข้ากลุ่มครั้งแรก)
        if etype == "message":
            msg = event.get("message", {}) or {}
            text = (msg.get("text") or "").strip().lower()
            reply_token = event.get("replyToken")
            if text in ("id", "groupid", "group id", "ไอดี") and reply_token:
                reply_ok = reply_text(
                    reply_token,
                    f"ID ของห้องนี้คือ:\n{sid}\n\n"
                    "เอาไปใส่ LINE_TARGET_ID ใน .env แล้ว restart backend",
                )
                log.info("webhook id reply_ok=%s source=%s id=%s", reply_ok, stype, sid)

    return {"ok": True}


@router.get("/status")
def status(_: Employee = Depends(require_manager)):
    """ดูว่าตั้งค่า LINE ครบหรือยัง (ไม่โชว์ token จริง)"""
    token = settings.line_channel_access_token.strip()
    return {
        "enabled": settings.line_notify_enabled,
        "has_access_token": bool(token),
        "access_token_preview": (token[:6] + "..." + token[-4:]) if token else "",
        "has_channel_secret": bool(settings.line_channel_secret.strip()),
        "target_id": settings.line_target_id.strip(),
        "ready": is_configured(),
    }


@router.post("/test")
def send_test(_: Employee = Depends(require_manager)):
    """ยิงข้อความทดสอบเข้ากลุ่ม (เฉพาะผู้จัดการ)"""
    if not is_configured():
        return {
            "sent": False,
            "detail": "ยังตั้งค่าไม่ครบ — ต้องมี LINE_CHANNEL_ACCESS_TOKEN "
            "และ LINE_TARGET_ID ใน .env แล้ว restart backend",
        }
    ok = push_text(
        "🔔 ทดสอบการแจ้งเตือนจากระบบเช็คอิน THANAKON-ROOM\n"
        "ถ้าเห็นข้อความนี้ในกลุ่ม แปลว่าตั้งค่าเรียบร้อยแล้วครับ"
    )
    return {
        "sent": ok,
        "detail": "ส่งสำเร็จ" if ok else "ส่งไม่สำเร็จ — ดู log ของ backend",
    }
