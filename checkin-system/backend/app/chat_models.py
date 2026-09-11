from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    __table_args__ = (
        UniqueConstraint("sender_id", "client_id", name="uq_chat_sender_client"),
        Index("ix_chat_pair_id", "sender_id", "recipient_id", "id"),
        Index("ix_chat_unread", "recipient_id", "read_at", "sender_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("employees.id"))
    recipient_id: Mapped[int] = mapped_column(ForeignKey("employees.id"))
    client_id: Mapped[str] = mapped_column(String(36))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
