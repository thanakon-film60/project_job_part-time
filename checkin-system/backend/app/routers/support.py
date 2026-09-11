"""ห้องช่วยเหลือระยะไกล (IT support) — วิดีโอคอล 1 ต่อ 1 + วาดชี้จุดบนภาพของผู้ใช้

ทำไมไม่ต้องลงไลบรารีวิดีโอฝั่ง Python:
  * ภาพ/เสียง = WebRTC ต่อตรงระหว่างเบราว์เซอร์สองฝั่ง ไม่วิ่งผ่านเซิร์ฟเวอร์นี้
    (เซิร์ฟเวอร์จึงไม่เห็นภาพ ไม่เปลือง bandwidth และไม่มีการบันทึกวิดีโอ)
  * สัญญาณนัดพบ (SDP/ICE) + เส้นที่ผู้ช่วยวาด = ส่งผ่าน WebSocket ของ FastAPI ตัวนี้
    ซึ่งเป็นของ Starlette อยู่แล้ว — uvicorn[standard] แถม websockets มาให้ ไม่ต้องลงเพิ่ม
  * ถ้าวันหลังอยากอัดวิดีโอเก็บไว้ที่เซิร์ฟเวอร์ ค่อยเพิ่ม aiortc เข้ามาเป็น peer อีกตัว
    โดยไม่ต้องแก้ฝั่งหน้าเว็บเลย

ฝั่งผู้ช่วย (host) ต้องล็อกอิน ส่วนฝั่งผู้ใช้ (guest) เข้าด้วยลิงก์ลับแล้วกดอนุญาตกล้องอย่างเดียว
ลิงก์ = กุญแจ จึงต้องสุ่มยาวและมีวันหมดอายุเสมอ
"""
import asyncio
import json
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Request,
    Response,
    WebSocket,
    WebSocketDisconnect,
)
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..database import SessionLocal, get_db
from ..models import Employee
from ..security import employee_from_token, get_current_employee
from ..support_models import STATUS_ACTIVE, STATUS_ENDED, STATUS_WAITING, SupportSession

router = APIRouter(prefix="/support", tags=["support"])

# path ของ "หน้าเว็บ" ฝั่งผู้ใช้ (React) — คนละอันกับ /support ที่เป็น API
GUEST_PATH = "/remote-help"

ROLE_HOST = "host"
ROLE_GUEST = "guest"

# ชนิดข้อความที่ยอมส่งต่อให้อีกฝั่ง — ที่ไม่อยู่ในนี้จะถูกทิ้ง
# กันไม่ให้ห้องนี้กลายเป็นช่องส่งข้อมูลอะไรก็ได้ระหว่างคนนอกสองคน
RELAYABLE = frozenset(
    {
        "offer", "answer", "ice", "renegotiate",          # นัดพบ WebRTC
        "draw", "draw_append", "draw_move", "draw_end",   # เส้นที่ผู้ช่วยวาด
        "undo", "clear", "pointer",
        "freeze", "unfreeze",                             # หยุดภาพนิ่งไว้วาดทับ
        "chat", "media", "hangup",
    }
)
# ~2MB ต่อข้อความ เผื่อภาพเฟรมที่หยุดไว้ (ส่งเป็น base64) — ใหญ่กว่านี้ถือว่าผิดปกติ
MAX_MESSAGE_CHARS = 2_000_000

# รหัสปิดสายที่ฝั่งหน้าเว็บเอาไปแปลงเป็นข้อความไทย
CLOSE_BAD_ROLE = 4400
CLOSE_UNAUTHORIZED = 4401
CLOSE_NOT_FOUND = 4404
CLOSE_REPLACED = 4409
CLOSE_CLOSED_ROOM = 4410


# ---------------------------------------------------------------- ทะเบียนห้อง
class _Room:
    """ห้องหนึ่ง = หนึ่งเซสชัน มีได้ผู้ช่วย 1 + ผู้ใช้ 1

    เข้าซ้ำบทบาทเดิม (เช่นรีเฟรชหน้า) ตัวเก่าจะถูกเตะออก ไม่ใช่ปฏิเสธตัวใหม่
    ไม่งั้นรีเฟรชทีเดียวแล้วเข้าห้องเดิมไม่ได้จนกว่า socket ค้างจะหมดเวลาเอง
    """

    __slots__ = ("peers",)

    def __init__(self) -> None:
        self.peers: dict[str, WebSocket] = {}


_rooms: dict[str, _Room] = {}
_rooms_lock = asyncio.Lock()


def _other(role: str) -> str:
    return ROLE_GUEST if role == ROLE_HOST else ROLE_HOST


async def _join_room(code: str, role: str, ws: WebSocket) -> WebSocket | None:
    """ลงทะเบียนเข้าห้อง คืน socket ตัวเก่าของบทบาทนี้ที่ต้องปิด (ถ้ามี)"""
    async with _rooms_lock:
        room = _rooms.setdefault(code, _Room())
        previous = room.peers.get(role)
        room.peers[role] = ws
        return previous


async def _leave_room(code: str, role: str, ws: WebSocket) -> None:
    async with _rooms_lock:
        room = _rooms.get(code)
        if room is None:
            return
        # ถ้าถูกตัวใหม่แทนที่ไปแล้ว อย่าเผลอลบของตัวใหม่ทิ้ง
        if room.peers.get(role) is ws:
            room.peers.pop(role, None)
        if not room.peers:
            _rooms.pop(code, None)


async def _peer_socket(code: str, role: str) -> WebSocket | None:
    async with _rooms_lock:
        room = _rooms.get(code)
        return room.peers.get(_other(role)) if room else None


async def _room_sockets(code: str) -> list[WebSocket]:
    async with _rooms_lock:
        room = _rooms.get(code)
        return list(room.peers.values()) if room else []


async def _send(ws: WebSocket, payload: dict) -> bool:
    """ส่งข้อความแบบไม่ให้ปลายทางที่ตายแล้วลากฝั่งที่ยังดีอยู่ล้มไปด้วย"""
    try:
        await ws.send_json(payload)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------- ตัวช่วยทั่วไป
def _iso(value: datetime | None) -> str | None:
    return value.replace(tzinfo=timezone.utc).isoformat() if value else None


def _join_url(code: str) -> str | None:
    """ลิงก์เต็มสำหรับส่งให้ผู้ใช้ — ได้ก็ต่อเมื่อตั้ง SUPPORT_PUBLIC_BASE_URL ไว้

    ถ้าไม่ได้ตั้ง หน้าเว็บจะประกอบเองจากโดเมนที่เปิดอยู่ (แม่นกว่าเดาจากฝั่งเซิร์ฟเวอร์
    ที่มองเห็นแค่ 127.0.0.1 เพราะอยู่หลัง reverse proxy ของ IIS)
    """
    base = settings.support_public_base_url.strip().rstrip("/")
    return f"{base}{GUEST_PATH}/{code}" if base else None


def _session_out(row: SupportSession) -> dict:
    return {
        "code": row.code,
        "title": row.title,
        "guest_label": row.guest_label,
        "status": row.status,
        "created_at": _iso(row.created_at),
        "expires_at": _iso(row.expires_at),
        "guest_joined_at": _iso(row.guest_joined_at),
        "ended_at": _iso(row.ended_at),
        "join_path": f"{GUEST_PATH}/{row.code}",
        "join_url": _join_url(row.code),
    }


def _expire_stale(db: Session, host_id: int) -> None:
    """ปิดห้องที่เลยเวลาให้อัตโนมัติ — ไม่ต้องมี cron แยก"""
    now = datetime.utcnow()
    changed = (
        db.query(SupportSession)
        .filter(
            SupportSession.host_id == host_id,
            SupportSession.status != STATUS_ENDED,
            SupportSession.expires_at <= now,
        )
        .update(
            {SupportSession.status: STATUS_ENDED, SupportSession.ended_at: now},
            synchronize_session=False,
        )
    )
    if changed:
        db.commit()


class CreateSession(BaseModel):
    title: str = Field(default="", max_length=160)
    guest_label: str = Field(default="", max_length=120)


# ---------------------------------------------------------------- REST (ฝั่งผู้ช่วย)
@router.get("/ice-servers")
def ice_servers(response: Response):
    """ค่า ICE ที่เบราว์เซอร์ใช้หาเส้นทางต่อตรง — ฝั่งผู้ใช้ที่ไม่ได้ล็อกอินก็ต้องใช้"""
    response.headers["Cache-Control"] = "no-store"
    return {"ice_servers": settings.ice_servers_list}


@router.post("/sessions")
def create_session(
    payload: CreateSession,
    response: Response,
    me: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"
    _expire_stale(db, me.id)

    open_rooms = (
        db.query(SupportSession)
        .filter(SupportSession.host_id == me.id, SupportSession.status != STATUS_ENDED)
        .count()
    )
    if open_rooms >= settings.support_max_open_sessions:
        raise HTTPException(409, "มีห้องที่เปิดค้างอยู่มากเกินไป กรุณาปิดห้องเก่าก่อน")

    row = SupportSession(
        # token_urlsafe(24) = 32 ตัวอักษร สุ่มจริง เดาไม่ได้ในทางปฏิบัติ
        code=secrets.token_urlsafe(24),
        host_id=me.id,
        title=payload.title.strip(),
        guest_label=payload.guest_label.strip(),
        status=STATUS_WAITING,
        expires_at=datetime.utcnow() + timedelta(minutes=settings.support_session_ttl_minutes),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _session_out(row)


@router.get("/sessions")
def list_sessions(
    response: Response,
    limit: int = Query(20, ge=1, le=100),
    me: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"
    _expire_stale(db, me.id)
    rows = (
        db.query(SupportSession)
        .filter(SupportSession.host_id == me.id)
        .order_by(SupportSession.id.desc())
        .limit(limit)
        .all()
    )
    return {"sessions": [_session_out(row) for row in rows]}


def _owned_session(db: Session, code: str, me: Employee) -> SupportSession:
    row = db.query(SupportSession).filter(SupportSession.code == code).first()
    if row is None or row.host_id != me.id:
        raise HTTPException(404, "ไม่พบห้องช่วยเหลือนี้")
    return row


@router.get("/sessions/{code}")
def session_detail(
    code: str,
    response: Response,
    me: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"
    return _session_out(_owned_session(db, code, me))


@router.post("/sessions/{code}/end")
async def end_session(
    code: str,
    response: Response,
    me: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"

    def _close() -> dict:
        row = _owned_session(db, code, me)
        if row.status != STATUS_ENDED:
            row.status = STATUS_ENDED
            row.ended_at = datetime.utcnow()
            db.commit()
            db.refresh(row)
        return _session_out(row)

    result = await run_in_threadpool(_close)

    # ไล่ทั้งสองฝั่งออกจากห้องทันที ไม่ต้องรอให้รู้ตัวเอง
    for ws in await _room_sockets(code):
        await _send(ws, {"type": "ended"})
        try:
            await ws.close(code=CLOSE_CLOSED_ROOM)
        except Exception:
            pass
    return result


@router.get("/sessions/{code}/qr.svg")
def session_qr(
    code: str,
    request: Request,
    origin: str = Query("", max_length=200),
    me: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """QR ของลิงก์เชิญ — ให้ผู้ใช้ที่นั่งหน้าคอมสแกนด้วยมือถือเพื่อส่องของจริงให้ดู"""
    _owned_session(db, code, me)
    try:
        import qrcode
        from qrcode.image.svg import SvgPathImage
    except ImportError:  # ยังไม่ได้ลง — หน้าเว็บจะซ่อนปุ่ม QR ไปเอง
        raise HTTPException(503, "ยังไม่ได้ติดตั้งไลบรารี qrcode (pip install -r requirements.txt)")

    base = (settings.support_public_base_url or origin or str(request.base_url)).strip().rstrip("/")
    parsed = urlparse(base)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise HTTPException(400, "ระบุโดเมนของหน้าเว็บไม่ถูกต้อง")

    image = qrcode.make(
        f"{parsed.scheme}://{parsed.netloc}{GUEST_PATH}/{code}",
        image_factory=SvgPathImage,
    )
    return Response(
        content=image.to_string(encoding="unicode"),
        media_type="image/svg+xml",
        headers={"Cache-Control": "no-store"},
    )


# ---------------------------------------------------------------- REST (ฝั่งผู้ใช้ ไม่ต้องล็อกอิน)
@router.get("/guest/{code}")
def guest_info(code: str, response: Response, db: Session = Depends(get_db)):
    """ข้อมูลเท่าที่ผู้ใช้ควรเห็นก่อนตัดสินใจกดอนุญาตกล้อง

    ตั้งใจบอกว่า "ใคร" เป็นคนขอ เพราะการเปิดกล้องให้คนแปลกหน้าคือความเสี่ยง
    ผู้ใช้ต้องเห็นชื่อผู้ช่วยแล้วเทียบกับคนที่ส่งลิงก์มาให้ได้
    """
    response.headers["Cache-Control"] = "no-store"
    row = db.query(SupportSession).filter(SupportSession.code == code).first()
    if row is None:
        raise HTTPException(404, "ลิงก์นี้ใช้ไม่ได้แล้ว")
    host = db.get(Employee, row.host_id)
    reason = None
    if row.status == STATUS_ENDED:
        reason = "ห้องนี้ถูกปิดไปแล้ว"
    elif row.is_expired:
        reason = "ลิงก์หมดอายุแล้ว กรุณาขอลิงก์ใหม่"
    return {
        "code": row.code,
        "title": row.title,
        "host_name": host.full_name if host else "ผู้ดูแลระบบ",
        "status": row.status,
        "expires_at": _iso(row.expires_at),
        "joinable": row.is_open,
        "reason": reason,
    }


# ---------------------------------------------------------------- WebSocket (signaling)
def _authorize_ws(code: str, role: str, token: str) -> tuple[int | None, str]:
    """ตรวจสิทธิ์เข้าห้องแบบ sync — คืน (รหัสปิดสาย, ชื่อผู้ช่วย); ผ่านแล้วรหัสจะเป็น None"""
    db = SessionLocal()
    try:
        row = db.query(SupportSession).filter(SupportSession.code == code).first()
        if row is None:
            return CLOSE_NOT_FOUND, ""
        if role == ROLE_HOST:
            me = employee_from_token(token, db) if token else None
            if me is None or me.id != row.host_id:
                return CLOSE_UNAUTHORIZED, ""
        if not row.is_open:
            return CLOSE_CLOSED_ROOM, ""
        host = db.get(Employee, row.host_id)
        return None, (host.full_name if host else "")
    finally:
        db.close()


def _mark_guest_joined(code: str) -> None:
    db = SessionLocal()
    try:
        row = db.query(SupportSession).filter(SupportSession.code == code).first()
        if row is None or row.status == STATUS_ENDED:
            return
        row.status = STATUS_ACTIVE
        if row.guest_joined_at is None:
            row.guest_joined_at = datetime.utcnow()
        db.commit()
    finally:
        db.close()


@router.websocket("/ws/{code}")
async def signaling(
    websocket: WebSocket,
    code: str,
    role: str = Query(...),
    token: str = Query(""),
):
    """ส่งต่อข้อความระหว่างผู้ช่วยกับผู้ใช้ — เซิร์ฟเวอร์ไม่ตีความ SDP หรือเส้นที่วาดเลย

    รับโทเค็นทาง query string เพราะ WebSocket ในเบราว์เซอร์ตั้ง header Authorization ไม่ได้
    (โทเค็นจึงอาจติดไปกับ log ของ proxy — ถ้ากังวลให้ลด ACCESS_TOKEN_EXPIRE_MINUTES ลง)
    """
    if role not in (ROLE_HOST, ROLE_GUEST):
        await websocket.close(code=CLOSE_BAD_ROLE)
        return

    close_code, host_name = await run_in_threadpool(_authorize_ws, code, role, token)
    if close_code is not None:
        await websocket.close(code=close_code)
        return

    await websocket.accept()
    if role == ROLE_GUEST:
        await run_in_threadpool(_mark_guest_joined, code)

    stale = await _join_room(code, role, websocket)
    if stale is not None:
        await _send(stale, {"type": "replaced"})
        try:
            await stale.close(code=CLOSE_REPLACED)
        except Exception:
            pass

    peer = await _peer_socket(code, role)
    await _send(
        websocket,
        {"type": "ready", "role": role, "host_name": host_name, "peer_online": peer is not None},
    )
    if peer is not None:
        await _send(peer, {"type": "peer", "role": role, "state": "joined"})

    try:
        while True:
            raw = await websocket.receive_text()
            if len(raw) > MAX_MESSAGE_CHARS:
                continue
            try:
                message = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(message, dict):
                continue

            kind = message.get("type")
            if kind == "ping":  # กัน proxy ตัดสายตอนเงียบนาน ๆ
                await _send(websocket, {"type": "pong"})
                continue
            if kind not in RELAYABLE:
                continue

            message["from"] = role
            target = await _peer_socket(code, role)
            if target is None:
                await _send(websocket, {"type": "peer", "role": _other(role), "state": "offline"})
                continue
            await _send(target, message)
    except WebSocketDisconnect:
        pass
    finally:
        await _leave_room(code, role, websocket)
        remaining = await _peer_socket(code, role)
        if remaining is not None:
            await _send(remaining, {"type": "peer", "role": role, "state": "left"})
