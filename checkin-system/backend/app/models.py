from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


class Employee(Base):
    __tablename__ = "employees"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_code: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(200))
    email: Mapped[str] = mapped_column(String(200), unique=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_manager: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    national_id_encrypted: Mapped[str | None] = mapped_column(String(255), nullable=True)
    national_id_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    address_line: Mapped[str | None] = mapped_column(String(255), nullable=True)
    postal_code: Mapped[str | None] = mapped_column(String(5), nullable=True)
    subdistrict: Mapped[str | None] = mapped_column(String(120), nullable=True)
    district: Mapped[str | None] = mapped_column(String(120), nullable=True)
    province: Mapped[str | None] = mapped_column(String(120), nullable=True)
    department: Mapped[str | None] = mapped_column(String(120), nullable=True)
    position: Mapped[str | None] = mapped_column(String(120), nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    checkins: Mapped[list["CheckIn"]] = relationship(back_populates="employee")


class EmploymentOption(Base):
    __tablename__ = "employment_options"
    __table_args__ = (UniqueConstraint("kind", "name", name="uq_employment_option_kind_name"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(20), index=True)
    name: Mapped[str] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class EmployeeEvent(Base):
    __tablename__ = "employee_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    actor_employee_id: Mapped[int | None] = mapped_column(ForeignKey("employees.id"), nullable=True)
    event_type: Mapped[str] = mapped_column(String(40), index=True)
    title: Mapped[str] = mapped_column(String(200))
    detail: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)


class CheckIn(Base):
    __tablename__ = "checkins"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)

    # ประเภท: "in" (เข้างาน) หรือ "out" (ออกงาน)
    kind: Mapped[str] = mapped_column(String(10), default="in")

    timestamp: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, index=True
    )
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    distance_km: Mapped[float] = mapped_column(Float)
    within_geofence: Mapped[bool] = mapped_column(Boolean)
    # ชื่อสถานที่ที่เช็คอิน (รองรับหลายสาขา) — nullable เพื่อให้ข้อมูลเก่าที่ยังไม่มีค่ายังอ่านได้
    office_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    face_detected: Mapped[bool] = mapped_column(Boolean, default=False)
    photo_path: Mapped[str | None] = mapped_column(String(500), nullable=True)

    employee: Mapped["Employee"] = relationship(back_populates="checkins")


class FaceProfile(Base):
    """ประวัติใบหน้าที่บันทึกไว้ของพนักงาน (face enrollment)
    ใช้เก็บรูปใบหน้าอ้างอิงหลายรูปต่อคน เพื่อทำประวัติ/ตรวจสอบภายหลัง"""

    __tablename__ = "face_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    photo_path: Mapped[str] = mapped_column(String(500))
    source: Mapped[str] = mapped_column(String(20), default="web")  # web / mobile
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, index=True
    )
    # ลำดับที่พนักงานจัดเอง (0 = รูปแรก ใช้เป็นรูปประจำตัว)
    # NULL = ยังไม่เคยจัดลำดับ ให้เรียงตามเวลาที่บันทึก (ใหม่สุดขึ้นก่อน)
    sort_order: Mapped[int | None] = mapped_column(Integer, nullable=True)

    employee: Mapped["Employee"] = relationship()


class LocationPing(Base):
    """เก็บพิกัด GPS ต่อเนื่องที่ Flutter ส่งมา (เปิด GPS ตลอดเวลา)"""

    __tablename__ = "location_pings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id"), index=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, index=True
    )
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    distance_km: Mapped[float] = mapped_column(Float)
    within_geofence: Mapped[bool] = mapped_column(Boolean)
    # สถานที่ที่ใกล้ที่สุดตอนส่งพิกัดมา (รองรับหลายสาขา)
    office_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
