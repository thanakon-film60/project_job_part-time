from collections import defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..geofence import location_category, office_by_name
from ..employee_profiles import employee_profile
from ..models import CheckIn, Employee, EmployeeEvent, FaceProfile
from ..schemas import EmployeeHistoryOut, EmployeeProfileOut, GeofenceInfo
from ..security import require_manager

router = APIRouter(prefix="/reports", tags=["reports"])

# ---------------------------------------------------------------------------
# เวลาไทย
#
# ใน DB เก็บเป็น UTC (datetime.utcnow) ถ้าเอาไปหั่นเป็นวัน/เดือนตรงๆ จะเพี้ยน
# 7 ชั่วโมง — การลงเวลาช่วงเช้ามืดหรือหลังห้าโมงเย็นจะไปโผล่ผิดวัน และเวลาที่
# แสดงบนเว็บก็จะเป็นเวลา UTC ทุกอย่างในไฟล์นี้จึงแปลงเป็นเวลาไทยก่อนเสมอ
# ---------------------------------------------------------------------------
LOCAL_OFFSET = timedelta(hours=settings.timezone_offset_hours)
LOCAL_TZ = timezone(LOCAL_OFFSET)


def _to_local(dt: datetime) -> datetime:
    """เวลา UTC ที่เก็บใน DB -> เวลาไทย (naive)"""
    return dt + LOCAL_OFFSET


def _local_day(dt: datetime) -> str:
    """วันที่ตามเวลาไทย ใช้เป็น key ของปฏิทิน"""
    return _to_local(dt).strftime("%Y-%m-%d")


def _local_iso(dt: datetime) -> str:
    """ISO ที่ติด offset +07:00 มาด้วย

    ต้องมี offset ไม่งั้น JavaScript จะตีความว่าเป็นเวลาท้องถิ่นของเครื่อง
    ผู้ใช้แล้วแสดงตัวเลขของ UTC ออกมาตรงๆ (เช่น 11:41 กลายเป็น 04:41)
    """
    return _to_local(dt).replace(tzinfo=LOCAL_TZ).isoformat()


def _is_home(record: CheckIn) -> bool:
    """ลงเวลาไว้ที่บ้าน

    อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่นับเป็นเวลาเข้างาน/ออกงานของวันนั้น
    (พนักงานยังต้องเข้าสู่ระบบทุกวัน ระบบจึงยังรู้ว่าอยู่ที่ไหน)
    """
    return location_category(office_by_name(record.office_name)) == "home"


def _month_range_utc(year: int, month: int) -> tuple[datetime, datetime]:
    """ขอบเขตของเดือนนั้น "ตามเวลาไทย" แปลงกลับเป็น UTC เพื่อใช้ query

    ใช้ช่วงเวลาแทน extract(year/month) เพราะ extract ทำงานบนค่า UTC ที่เก็บไว้
    ทำให้การลงเวลาต้นเดือน/ปลายเดือนตกไปอยู่ผิดเดือน
    """
    start_local = datetime(year, month, 1)
    if month == 12:
        end_local = datetime(year + 1, 1, 1)
    else:
        end_local = datetime(year, month + 1, 1)
    return start_local - LOCAL_OFFSET, end_local - LOCAL_OFFSET


@router.get("/geofence", response_model=GeofenceInfo)
def geofence_info():
    offices = settings.offices_list
    first = offices[0]
    return GeofenceInfo(
        offices=offices,
        # ฟิลด์เดิม = สถานที่แรก (ให้ client เก่ายังทำงานได้)
        office_name=first["name"],
        office_lat=first["lat"],
        office_lng=first["lng"],
        radius_km=first["radius_km"],
    )


@router.get("/employees", response_model=list[EmployeeProfileOut])
def list_employees(
    _: Employee = Depends(require_manager), db: Session = Depends(get_db)
):
    employees = db.query(Employee).order_by(Employee.full_name).all()
    return [employee_profile(employee) for employee in employees]


@router.get("/employees/{employee_id}/history", response_model=EmployeeHistoryOut)
def employee_history(
    employee_id: int,
    year: int = Query(..., ge=2000, le=2100),
    month: int = Query(..., ge=1, le=12),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """ประวัติลงเวลารายบุคคลในเดือนที่เลือก สำหรับ Boss เท่านั้น."""
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if employee is None:
        raise HTTPException(status_code=404, detail="ไม่พบพนักงาน")

    start_utc, end_utc = _month_range_utc(year, month)
    checkins = (
        db.query(CheckIn)
        .filter(
            CheckIn.employee_id == employee_id,
            CheckIn.timestamp >= start_utc,
            CheckIn.timestamp < end_utc,
        )
        .order_by(CheckIn.timestamp.desc())
        .all()
    )
    events = (
        db.query(EmployeeEvent)
        .filter(EmployeeEvent.employee_id == employee_id)
        .order_by(EmployeeEvent.created_at.desc())
        .all()
    )
    if not events:
        legacy_event = EmployeeEvent(
            employee_id=employee.id,
            actor_employee_id=None,
            event_type="legacy_account",
            title="บัญชีเดิมก่อนระบบแฟ้มพนักงาน",
            detail={"note": "นำบัญชีและประวัติเดิมมาประสานกับโครงสร้างใหม่แล้ว"},
            created_at=employee.created_at,
        )
        db.add(legacy_event)
        db.commit()
        db.refresh(legacy_event)
        events = [legacy_event]

    faces = (
        db.query(FaceProfile)
        .filter(FaceProfile.employee_id == employee_id)
        .order_by(FaceProfile.created_at.desc())
        .all()
    )
    return EmployeeHistoryOut(
        employee=employee_profile(employee),
        year=year,
        month=month,
        checkins=checkins,
        face_profiles=faces,
        events=events,
    )


@router.get("/calendar")
def calendar(
    employee_id: int = Query(...),
    year: int = Query(...),
    month: int = Query(...),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """
    สรุปการเข้า/ออกงานรายวันของพนักงานคนหนึ่งในเดือนที่เลือก
    ใช้ป้อนให้ปฏิทินฝั่ง React ให้เจ้านายดู
    """
    start_utc, end_utc = _month_range_utc(year, month)
    rows = (
        db.query(CheckIn)
        .filter(
            CheckIn.employee_id == employee_id,
            CheckIn.timestamp >= start_utc,
            CheckIn.timestamp < end_utc,
        )
        .order_by(CheckIn.timestamp)
        .all()
    )

    by_day: dict[str, dict] = defaultdict(
        lambda: {
            "date": None,
            "first_in": None,
            "last_out": None,
            "within_geofence": False,
            # วันนั้นมีแต่การลงเวลาที่บ้าน = ไม่ได้ไปทำงาน
            "home_only": True,
            "count": 0,
        }
    )
    for r in rows:
        day = _local_day(r.timestamp)
        d = by_day[day]
        d["date"] = day
        d["count"] += 1
        if r.within_geofence:
            d["within_geofence"] = True

        # อยู่บ้านไม่ใช่การเข้างาน จึงไม่เอามาเป็นเวลาเข้า/ออกของวันนั้น
        if _is_home(r):
            continue
        d["home_only"] = False

        t = _local_iso(r.timestamp)
        if r.kind == "in":
            if d["first_in"] is None or t < d["first_in"]:
                d["first_in"] = t
        elif r.kind == "out":
            if d["last_out"] is None or t > d["last_out"]:
                d["last_out"] = t

    return {
        "employee_id": employee_id,
        "year": year,
        "month": month,
        "days": sorted(by_day.values(), key=lambda x: x["date"]),
    }


def _location_label(office_name: str | None, within_geofence: bool) -> str:
    """แปลงชื่อสถานที่ภายในให้เป็นข้อความสั้นที่ใช้บนปฏิทิน"""
    name = (office_name or "").strip()
    if "บ้าน" in name:
        return "อยู่ที่บ้าน"
    if name:
        return name
    return "ในออฟฟิศ" if within_geofence else "นอกเขต"


def _location_rank(label: str) -> int:
    """ลำดับการแสดงป้ายสถานที่ — ที่ทำงานต้องมาก่อน แล้วค่อยตามด้วยที่บ้าน

    หัวหน้าเปิดดูเพื่อจะรู้ว่า "วันนี้ไปทำงานที่ไหน" ถ้าป้าย "อยู่ที่บ้าน"
    ขึ้นก่อน จะอ่านผ่านๆ แล้วเข้าใจผิดว่าอยู่บ้านทั้งวัน
    """
    if label == "อยู่ที่บ้าน":
        return 2
    if label == "นอกเขต":
        return 1
    return 0


@router.get("/team-calendar")
def team_calendar(
    year: int = Query(...),
    month: int = Query(..., ge=1, le=12),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """สรุปว่าแต่ละวันมีพนักงานคนใดลงเวลา เพื่อใช้ในปฏิทินรวมของ Boss"""
    start_utc, end_utc = _month_range_utc(year, month)
    rows = (
        db.query(CheckIn, Employee)
        .join(Employee, Employee.id == CheckIn.employee_id)
        .filter(
            Employee.is_manager.is_(False),
            CheckIn.timestamp >= start_utc,
            CheckIn.timestamp < end_utc,
        )
        .order_by(CheckIn.timestamp)
        .all()
    )

    people_by_day: dict[str, dict[int, dict]] = defaultdict(dict)
    for checkin, employee in rows:
        day = _local_day(checkin.timestamp)
        person = people_by_day[day].setdefault(
            employee.id,
            {
                "employee_id": employee.id,
                "employee_code": employee.employee_code,
                "full_name": employee.full_name,
                "first_in": None,
                "last_out": None,
                "locations": [],
                # วันนั้นมีแต่การลงเวลาที่บ้าน = ไม่ได้ไปทำงาน
                "home_only": True,
                "count": 0,
            },
        )
        person["count"] += 1

        location = _location_label(checkin.office_name, checkin.within_geofence)
        if location not in person["locations"]:
            person["locations"].append(location)

        # อยู่บ้านไม่ใช่การเข้างาน จึงไม่เอามาเป็นเวลาเข้า/ออกของวันนั้น
        if _is_home(checkin):
            continue
        person["home_only"] = False

        timestamp = _local_iso(checkin.timestamp)
        if checkin.kind == "in" and (
            person["first_in"] is None or timestamp < person["first_in"]
        ):
            person["first_in"] = timestamp
        elif checkin.kind == "out" and (
            person["last_out"] is None or timestamp > person["last_out"]
        ):
            person["last_out"] = timestamp

    # เรียงป้ายสถานที่: ที่ทำงานก่อน แล้วค่อยนอกเขต/ที่บ้าน
    # (sorted ของ Python เสถียร ป้ายที่ระดับเดียวกันจึงยังเรียงตามเวลาที่ลงจริง)
    for people in people_by_day.values():
        for person in people.values():
            person["locations"].sort(key=_location_rank)

    days = [
        {
            "date": day,
            "people": sorted(people.values(), key=lambda item: item["full_name"]),
        }
        for day, people in sorted(people_by_day.items())
    ]
    return {"year": year, "month": month, "days": days}
