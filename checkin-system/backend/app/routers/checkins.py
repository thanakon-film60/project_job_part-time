import logging
import os
import uuid
from datetime import datetime, time, timedelta

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    UploadFile,
)
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..geofence import (
    describe_offices,
    evaluate_location,
    location_category,
    location_category_label,
    office_by_name,
)
from ..models import CheckIn, Employee
from ..notify_line import push_text
from ..schemas import CheckInOut
from ..security import get_current_employee

router = APIRouter(prefix="/checkins", tags=["checkins"])
log = logging.getLogger("checkins")

# ใน DB เก็บเวลาเป็น UTC — ต้องบวกออฟเซ็ตก่อนถึงจะตัด "วันนี้" ตามเวลาไทยได้ถูก
LOCAL_OFFSET = timedelta(hours=settings.timezone_offset_hours)


def _distance_text(distance_km: float) -> str:
    return (
        f"{distance_km * 1000:.0f} เมตร"
        if distance_km < 1
        else f"{distance_km:.2f} กม."
    )


def _employee_display_name(emp: Employee) -> str:
    return (emp.full_name or "").strip() or emp.employee_code


def notify_checkin(emp: Employee, record: CheckIn, office: dict | None = None) -> None:
    """แจ้งเข้ากลุ่ม LINE ว่ามีคนเช็คอิน/เช็คเอาท์

    ห่อ try ทั้งก้อน — ถ้า LINE มีปัญหาต้องไม่ทำให้การเช็คอินล้มเหลว
    """
    try:
        local_time = record.timestamp + timedelta(
            hours=settings.timezone_offset_hours
        )
        action = "เข้างาน" if record.kind == "in" else "ออกจากงาน"
        time_text = local_time.strftime("%H:%M น. %d/%m/%Y")
        distance_text = _distance_text(record.distance_km)
        office_info = office or office_by_name(record.office_name)
        category_label = location_category_label(office_info)
        office_name = record.office_name or (office_info or {}).get("name") or "-"

        # อยู่บ้าน = ไม่ได้ไปทำงาน การลงเวลาที่บ้านจึงเป็นแค่ "กลับถึงบ้านแล้ว"
        # ไม่ใช่การเข้างาน และไม่ต้องมีออกงานตามมา
        if location_category(office_info) == "home":
            headline = f"{_employee_display_name(emp)} กลับถึงบ้านแล้ว ({time_text})"
            note = "ไม่นับเป็นการเข้างาน (อยู่บ้าน = ไม่ได้ไปทำงาน)"
        else:
            headline = (
                f"{_employee_display_name(emp)} ได้ทำการ{action}แล้ว ({time_text})"
            )
            note = f"ประเภทสถานที่: {category_label}"

        push_text(
            f"{headline}\n"
            f"{note}\n"
            f"สถานที่ใกล้สุด: {office_name}\n"
            f"ระยะห่างจาก{category_label}: {distance_text}"
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
    checkout_only = kind == "out"
    distance_km, within, office = evaluate_location(
        latitude, longitude, work_only=checkout_only
    )

    # เงื่อนไข: ต้องอยู่ในรัศมีทั้งตอนเข้างานและออกงาน
    # ตรวจที่ backend เสมอ เพื่อป้องกัน client เก่าหรือการส่ง request ข้าม UI
    if not within:
        action = "ออกงาน" if kind == "out" else "เข้างาน"
        raise HTTPException(
            status_code=422,
            detail=f"ไม่สามารถ{action}ได้ เพราะอยู่นอกเขตที่กำหนด — "
            f"ใกล้สุดคือ {office['name']} "
            f"ห่าง {distance_km:.2f} กม. (อนุญาตไม่เกิน {office['radius_km']} กม.) "
            f"| สถานที่ที่อนุญาต: {describe_offices(work_only=checkout_only)}",
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
    notify_checkin(emp, record, office)

    return record


@router.get("/me", response_model=list[CheckInOut])
def my_checkins(
    days: int | None = Query(
        None,
        ge=1,
        le=366,
        description="ย้อนหลังกี่วัน นับตามเวลาไทย (ไม่ส่ง = ทั้งหมด)",
    ),
    limit: int | None = Query(None, ge=1, le=1000),
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ประวัติการลงเวลาของตัวเอง — แอปมือถือใช้ days=1 ดึงเฉพาะของวันนี้

    ไม่ส่งพารามิเตอร์มา = พฤติกรรมเดิม (คืนทั้งหมด) เพื่อให้ client รุ่นเก่าไม่พัง
    """
    query = db.query(CheckIn).filter(CheckIn.employee_id == emp.id)

    if days is not None:
        # ตัดวันตามเวลาไทยก่อน แล้วแปลงกลับเป็น UTC ให้ตรงกับที่เก็บใน DB
        # (days=1 = ตั้งแต่เที่ยงคืนของวันนี้ตามเวลาไทย)
        today_local = (datetime.utcnow() + LOCAL_OFFSET).date()
        start_local = datetime.combine(today_local, time.min) - timedelta(
            days=days - 1
        )
        query = query.filter(CheckIn.timestamp >= start_local - LOCAL_OFFSET)

    query = query.order_by(CheckIn.timestamp.desc())
    if limit is not None:
        query = query.limit(limit)
    return query.all()
