"""ห้องช่วยเหลือระยะไกล (Remote IT support) — ผู้ช่วยที่ล็อกอินคุยวิดีโอกับผู้ใช้ที่แค่กดอนุญาตกล้อง

ตารางนี้เก็บแค่ "ใบอนุญาตเข้าห้อง" ไม่ได้เก็บภาพหรือเสียง
ภาพ/เสียงวิ่งตรงระหว่างเบราว์เซอร์สองฝั่ง (WebRTC) ไม่ผ่านเซิร์ฟเวอร์และไม่มีการบันทึก
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base

# สถานะห้อง: รอผู้ใช้เข้า -> กำลังคุย -> ปิดแล้ว
STATUS_WAITING = "waiting"
STATUS_ACTIVE = "active"
STATUS_ENDED = "ended"


class SupportSession(Base):
    __tablename__ = "support_sessions"
    __table_args__ = (
        Index("ix_support_host_created", "host_id", "created_at"),
        Index("ix_support_status", "status", "expires_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # โทเค็นในลิงก์เชิญ — สุ่มแบบเดาไม่ได้ เพราะฝั่งผู้ใช้เข้าห้องโดยไม่ต้องล็อกอิน
    # (ใครถือลิงก์ = เข้าได้ จึงต้องยาวพอและมีวันหมดอายุเสมอ)
    code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    host_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    title: Mapped[str] = mapped_column(String(160), default="")
    guest_label: Mapped[str] = mapped_column(String(120), default="")
    status: Mapped[str] = mapped_column(String(16), default=STATUS_WAITING)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    guest_joined_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    @property
    def is_expired(self) -> bool:
        return datetime.utcnow() >= self.expires_at

    @property
    def is_open(self) -> bool:
        """ยังเข้าห้องได้อยู่ไหม (ยังไม่ปิด และยังไม่หมดอายุ)"""
        return self.status != STATUS_ENDED and not self.is_expired
