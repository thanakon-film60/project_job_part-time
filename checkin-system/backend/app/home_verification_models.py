"""ตารางสำหรับการยืนยันตัวตนรายวันตอนอยู่บ้าน

แยกจาก `checkins` โดยตั้งใจ — รายการที่บ้านไม่ใช่การเข้างาน จึงต้องไม่มีทางหลุด
ไปโผล่ในสูตรสาย/ชั่วโมงทำงานที่อ่านจากตาราง checkins
"""
from datetime import date, datetime

from sqlalchemy import (
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class HomeVerificationChallenge(Base):
    """โจทย์อายุสั้นที่ server ออกให้ก่อนเริ่มสแกน

    มีไว้กันการนำหลักฐานเก่ามาส่งใหม่ — ไม่ใช่เส้นตายว่าต้องยืนยันก่อนกี่โมง
    """

    __tablename__ = "home_verification_challenges"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    challenge_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    # คำสั่งที่ให้ผู้ใช้ทำตอนสแกน — server บันทึกว่าออกคำสั่งใด แต่ตรวจท่าในรูปไม่ได้
    action: Mapped[str] = mapped_column(String(60))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    # ใช้ได้ครั้งเดียว — มีค่าแล้วคือถูกใช้ยืนยันไปแล้ว
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class HomeVerification(Base):
    """ผลการยืนยันตัวตนที่บ้านหนึ่งครั้ง

    ไม่มี kind / เวลาเข้า-ออก / สถานะสาย โดยตั้งใจ: `verified_at` คือ
    "เวลายืนยันตัวตน" ไม่ใช่เวลาเข้างาน และห้ามนำไปคำนวณเวลาทำงาน
    """

    __tablename__ = "home_verifications"
    __table_args__ = (
        # กันคำขอซ้ำ: ส่ง request_id เดิมอีกครั้งต้องได้รายการเดิม ไม่ใช่รายการใหม่
        UniqueConstraint(
            "employee_id", "request_id", name="uq_home_verification_employee_request"
        ),
        # กันนำรูปเดิมมาใช้ยืนยันรอบใหม่ (ทั่วทั้งระบบ ไม่ใช่แค่ในบัญชีเดียว)
        UniqueConstraint("evidence_sha256", name="uq_home_verification_evidence"),
        Index("ix_home_verification_employee_date", "employee_id", "local_date"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    request_id: Mapped[str] = mapped_column(String(36))
    challenge_id: Mapped[str] = mapped_column(String(36))
    status: Mapped[str] = mapped_column(String(20), default="verified")

    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    location_accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    distance_km: Mapped[float] = mapped_column(Float)
    office_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    category: Mapped[str] = mapped_column(String(20), default="home")

    evidence_sha256: Mapped[str] = mapped_column(String(64))
    # ลายนิ้วมือของคำขอ ใช้แยก "ส่งซ้ำเพราะเน็ตหลุด" ออกจาก "ใช้ ID เดิมแต่เปลี่ยนเนื้อหา"
    payload_fingerprint: Mapped[str] = mapped_column(String(64))
    photo_path: Mapped[str | None] = mapped_column(String(500), nullable=True)

    verified_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, index=True
    )
    # วันตามเวลาไทยที่ server ตัดให้ — ใช้จัดกลุ่มรายวัน ไม่เชื่อวันจากเครื่องผู้ใช้
    local_date: Mapped[date] = mapped_column(Date, index=True)
