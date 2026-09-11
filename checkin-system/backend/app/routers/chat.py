"""Private boss/employee conversations. Every query is scoped to the authenticated employee."""
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, case, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from ..chat_models import ChatMessage
from ..database import get_db
from ..models import Employee
from ..security import get_current_employee

router = APIRouter(prefix="/chat", tags=["chat"])


class SendMessage(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    client_id: UUID

    @field_validator("body")
    @classmethod
    def meaningful_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("กรุณาพิมพ์ข้อความ")
        return value


class ReadMessages(BaseModel):
    through_id: int = Field(ge=1)


def chat_peer(db: Session, me: Employee, peer_id: int) -> Employee:
    peer = db.get(Employee, peer_id)
    if peer is None:
        raise HTTPException(404, "ไม่พบผู้รับข้อความ")
    if peer.id == me.id or bool(peer.is_manager) == bool(me.is_manager):
        raise HTTPException(403, "แชทนี้ใช้ระหว่างหัวหน้ากับพนักงานเท่านั้น")
    return peer


def pair_filter(me_id: int, peer_id: int):
    return or_(
        and_(ChatMessage.sender_id == me_id, ChatMessage.recipient_id == peer_id),
        and_(ChatMessage.sender_id == peer_id, ChatMessage.recipient_id == me_id),
    )


def message_out(message: ChatMessage) -> dict:
    return {
        "id": message.id, "sender_id": message.sender_id,
        "recipient_id": message.recipient_id, "client_id": message.client_id,
        "body": message.body,
        "created_at": message.created_at.replace(tzinfo=timezone.utc).isoformat(),
        "read_at": message.read_at.replace(tzinfo=timezone.utc).isoformat() if message.read_at else None,
    }


@router.get("/contacts")
def contacts(response: Response, me: Employee = Depends(get_current_employee), db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store"
    other_id = case((ChatMessage.sender_id == me.id, ChatMessage.recipient_id), else_=ChatMessage.sender_id)
    latest = (db.query(other_id.label("peer_id"), func.max(ChatMessage.id).label("message_id"))
        .filter(or_(ChatMessage.sender_id == me.id, ChatMessage.recipient_id == me.id))
        .group_by(other_id).subquery())
    unread = (db.query(ChatMessage.sender_id.label("peer_id"), func.count(ChatMessage.id).label("count"))
        .filter(ChatMessage.recipient_id == me.id, ChatMessage.read_at.is_(None))
        .group_by(ChatMessage.sender_id).subquery())
    last = aliased(ChatMessage)
    rows = (db.query(Employee, last, func.coalesce(unread.c.count, 0))
        .outerjoin(latest, latest.c.peer_id == Employee.id)
        .outerjoin(last, last.id == latest.c.message_id)
        .outerjoin(unread, unread.c.peer_id == Employee.id)
        .filter(Employee.is_manager.is_(not bool(me.is_manager)))
        .order_by(last.id.desc().nullslast(), Employee.full_name).all())
    return {"contacts": [{"id": peer.id, "full_name": peer.full_name,
        "employee_code": peer.employee_code, "is_manager": peer.is_manager,
        "unread_count": count, "last_message": message_out(message) if message else None}
        for peer, message, count in rows]}


@router.get("/messages/{peer_id}")
def messages(peer_id: int, response: Response, before_id: int | None = Query(None, ge=1),
             after_id: int | None = Query(None, ge=0), limit: int = Query(50, ge=1, le=100),
             me: Employee = Depends(get_current_employee), db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store"
    chat_peer(db, me, peer_id)
    if before_id is not None and after_id is not None:
        raise HTTPException(422, "เลือกก่อนหรือหลังข้อความอย่างใดอย่างหนึ่ง")
    query = db.query(ChatMessage).filter(pair_filter(me.id, peer_id))
    if before_id is not None:
        query = query.filter(ChatMessage.id < before_id)
    if after_id is not None:
        query = query.filter(ChatMessage.id > after_id).order_by(ChatMessage.id)
    else:
        query = query.order_by(ChatMessage.id.desc())
    rows = query.limit(limit + 1).all()
    more = len(rows) > limit
    rows = rows[:limit]
    if after_id is None:
        rows.reverse()
    read_through = db.query(func.max(ChatMessage.id)).filter(
        ChatMessage.sender_id == me.id, ChatMessage.recipient_id == peer_id,
        ChatMessage.read_at.is_not(None)).scalar()
    return {"messages": [message_out(row) for row in rows], "has_more": more,
            "peer_read_through_id": read_through or 0}


@router.post("/messages/{peer_id}")
def send_message(peer_id: int, payload: SendMessage, response: Response,
                 me: Employee = Depends(get_current_employee), db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store"
    chat_peer(db, me, peer_id)
    client_id = str(payload.client_id)
    existing = db.query(ChatMessage).filter_by(sender_id=me.id, client_id=client_id).first()
    if existing is None:
        existing = ChatMessage(sender_id=me.id, recipient_id=peer_id, client_id=client_id, body=payload.body)
        db.add(existing)
        try:
            db.commit()
            db.refresh(existing)
        except IntegrityError:
            db.rollback()
            existing = db.query(ChatMessage).filter_by(sender_id=me.id, client_id=client_id).first()
            if existing is None:
                raise
    if existing.recipient_id != peer_id or existing.body != payload.body:
        raise HTTPException(409, "รหัสส่งข้อความนี้ถูกใช้แล้ว กรุณาส่งเป็นข้อความใหม่")
    return message_out(existing)


@router.post("/read/{peer_id}")
def mark_read(peer_id: int, payload: ReadMessages, response: Response,
              me: Employee = Depends(get_current_employee), db: Session = Depends(get_db)):
    response.headers["Cache-Control"] = "no-store"
    chat_peer(db, me, peer_id)
    boundary = db.query(ChatMessage.id).filter(pair_filter(me.id, peer_id), ChatMessage.id == payload.through_id).first()
    if boundary is None:
        raise HTTPException(404, "ไม่พบข้อความในบทสนทนานี้")
    db.query(ChatMessage).filter(ChatMessage.sender_id == peer_id, ChatMessage.recipient_id == me.id,
        ChatMessage.id <= payload.through_id, ChatMessage.read_at.is_(None)).update(
            {ChatMessage.read_at: datetime.utcnow()}, synchronize_session=False)
    db.commit()
    return {"ok": True}
