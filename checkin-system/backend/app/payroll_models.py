"""บันทึกว่าแจ้งเตือนเงินเดือนรอบไหนส่งไปแล้วบ้าง

มีไว้อย่างเดียวคือ **กันส่งซ้ำ** — Scheduled Task ถูกตั้งให้ยิงวันละ 2 รอบ
และผู้ใช้ยังสั่งรันเองได้ตลอด ถ้าไม่มีตารางนี้ พนักงานจะได้ข้อความเดิมซ้ำ
หลายครั้งต่อวัน

คีย์ที่กันซ้ำคือ (รอบ, ชนิดข้อความ, พนักงาน) — เก็บผลลัพธ์ไว้ด้วยเพื่อให้
รู้ว่าที่ส่งไม่สำเร็จคือรอบไหน แล้วสั่งส่งซ้ำเฉพาะอันนั้นได้
"""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base

# ชนิดข้อความ — ใช้สตริงชุดนี้ทั้งใน CLI, API และ DB
NOTICE_CUTOFF = "cutoff"          # วันที่ 26 ตัดรอบ
NOTICE_CYCLE_START = "cycle_start"  # วันที่ 27 เริ่มรอบใหม่
NOTICE_PAYDAY = "payday"          # วันที่ 28 เงินออก

NOTICE_KINDS = (NOTICE_CUTOFF, NOTICE_CYCLE_START, NOTICE_PAYDAY)

NOTICE_LABELS = {
    NOTICE_CUTOFF: "ตัดรอบ",
    NOTICE_CYCLE_START: "เริ่มรอบใหม่",
    NOTICE_PAYDAY: "เงินเดือนออก",
}


class PayrollNotice(Base):
    """หนึ่งแถว = หนึ่ง "ครั้งที่พยายามส่ง" ไม่ใช่หนึ่งข้อความ

    ตั้งใจไม่ใส่ UNIQUE(period_key, kind, employee_id) เพราะการส่งซ้ำมีเหตุผล
    ที่ถูกต้องอยู่สองกรณี: ครั้งก่อนส่งไม่สำเร็จแล้วรอบถัดไปลองใหม่ กับหัวหน้า
    สั่ง force ส่งซ้ำเอง เก็บเป็นประวัติจึงตอบได้ว่า "ส่งไม่ผ่านกี่ครั้งแล้ว"
    ตัวกันซ้ำจริงคือ already_sent() ที่นับเฉพาะแถว ok=True
    """

    __tablename__ = "payroll_notices"
    __table_args__ = (
        Index("ix_payroll_notice_period", "period_key", "kind"),
        Index("ix_payroll_notice_lookup", "employee_id", "period_key", "kind", "ok"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)

    # วันจ่ายของรอบนั้นในรูปแบบ ISO เช่น "2026-09-28" — ไม่ซ้ำข้ามรอบแน่นอน
    period_key: Mapped[str] = mapped_column(String(10))
    kind: Mapped[str] = mapped_column(String(20))

    sent_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    ok: Mapped[bool] = mapped_column(Boolean, default=False)

    # ยอดสุทธิที่แจ้งไป เก็บไว้ตรวจย้อนหลังว่าตอนนั้นบอกตัวเลขอะไรไป
    # (ยอดคำนวณสดทุกครั้ง ถ้าแก้เกณฑ์ภายหลังตัวเลขจะไม่ตรงกับที่เคยส่ง)
    amount: Mapped[float | None] = mapped_column(Float, nullable=True)
