import logging
import os
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..geofence import describe_offices, evaluate_location
from ..models import CheckIn, Employee
from ..notify_line import push_text
from ..schemas import CheckInOut
from ..security import get_current_employee

router = APIRouter(prefix="/checkins", tags=["checkins"])
log = logging.getLogger("checkins")


def notify_checkin(emp: Employee, record: CheckIn) -> None:
    """แจ้งเข้ากลุ่ม LINE ว่ามีคนเช็คอิน/เช็คเอาท์

    ห่อ try ทั้งก้อน — ถ้า LINE มีปัญหาต้องไม่ทำให้การเช็คอินล้มเหลว
    """
    try:
        local_time = record.timestamp + timedelta(
            hours=settings.timezone_offset_hours
        )
        action = "เข้างาน" if record.kind == "in" else "ออกงาน"
        time_text = local_time.strftime("%H:%M น. %d/%m/%Y")
        distance_text = (
            f"{record.distance_km * 1000:.0f} เมตร"
            if record.distance_km < 1
            else f"{record.distance_km:.2f} กม."
        )
        push_text(
            f"ตอนนี้ฉันได้บันทึกการ{action}ของคุณแล้ว "
            f"({time_text}) ห่างจากจุดทำงาน {distance_text}"
        )
    except Exception as e:
        log.warning("แจ้งเตือน LINE ไม่สำเร็จ: %s", e)


@router.post("", response_model=CheckInOut)
async def create_checkin(
    latitude: float = Form(...),
    longitude: float = Form(...),
    kind: str = Form("in"),
    face_detected: bool = Form(False),
    photo: UploadFile | None = File(None),
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    if kind not in ("in", "out"):
        raise HTTPException(status_code=400, detail="kind ต้องเป็น 'in' หรือ 'out'")

    # รองรับหลายสถานที่ — ระบบเลือกที่ที่อยู่ในเขต (หรือใกล้ที่สุดถ้าไม่อยู่ในเขตเลย)
    distance_km, within, office = evaluate_location(latitude, longitude)

    # เงื่อนไข: ต้องอยู่ในรัศมี และต้องตรวจพบใบหน้า
    if not within:
        raise HTTPException(
            status_code=422,
            detail=f"อยู่นอกเขตที่กำหนด — ใกล้สุดคือ {office['name']} "
            f"ห่าง {distance_km:.2f} กม. (อนุญาตไม่เกิน {office['radius_km']} กม.) "
            f"| สถานที่ทั้งหมด: {describe_offices()}",
        )
    if not face_detected:
        raise HTTPException(
            status_code=422, detail="ไม่พบใบหน้า/liveness ไม่ผ่าน เช็คอินไม่ได้"
        )

    photo_path = None
    if photo is not None:
        os.makedirs(settings.storage_dir, exist_ok=True)
        ext = os.path.splitext(photo.filename or "")[1] or ".jpg"
        fname = f"{emp.employee_code}_{uuid.uuid4().hex}{ext}"
        full = os.path.join(settings.storage_dir, fname)
        with open(full, "wb") as f:
            f.write(await photo.read())
        photo_path = full

    record = CheckIn(
        employee_id=emp.id,
        kind=kind,
        timestamp=datetime.utcnow(),
        latitude=latitude,
        longitude=longitude,
        distance_km=distance_km,
        within_geofence=within,
        office_name=office["name"],
        face_detected=face_detected,
        photo_path=photo_path,
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    # แจ้งเข้ากลุ่ม LINE — ทำหลัง commit และห้ามให้พังจนกระทบการเช็คอิน
    notify_checkin(emp, record)

    return record


@router.get("/me", response_model=list[CheckInOut])
def my_checkins(
    emp: Employee = Depends(get_current_employee), db: Session = Depends(get_db)
):
    return (
        db.query(CheckIn)
        .filter(CheckIn.employee_id == emp.id)
        .order_by(CheckIn.timestamp.desc())
        .all()
    )
