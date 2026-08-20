from collections import defaultdict
from datetime import datetime

from fastapi import APIRouter, Depends, Query
from sqlalchemy import extract
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import CheckIn, Employee
from ..schemas import EmployeeOut, GeofenceInfo
from ..security import require_manager

router = APIRouter(prefix="/reports", tags=["reports"])


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


@router.get("/employees", response_model=list[EmployeeOut])
def list_employees(
    _: Employee = Depends(require_manager), db: Session = Depends(get_db)
):
    return db.query(Employee).order_by(Employee.full_name).all()


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
    rows = (
        db.query(CheckIn)
        .filter(
            CheckIn.employee_id == employee_id,
            extract("year", CheckIn.timestamp) == year,
            extract("month", CheckIn.timestamp) == month,
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
            "count": 0,
        }
    )
    for r in rows:
        day = r.timestamp.strftime("%Y-%m-%d")
        d = by_day[day]
        d["date"] = day
        d["count"] += 1
        if r.within_geofence:
            d["within_geofence"] = True
        t = r.timestamp.isoformat()
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


@router.get("/team-calendar")
def team_calendar(
    year: int = Query(...),
    month: int = Query(..., ge=1, le=12),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """สรุปว่าแต่ละวันมีพนักงานคนใดลงเวลา เพื่อใช้ในปฏิทินรวมของ Boss"""
    rows = (
        db.query(CheckIn, Employee)
        .join(Employee, Employee.id == CheckIn.employee_id)
        .filter(
            Employee.is_manager.is_(False),
            extract("year", CheckIn.timestamp) == year,
            extract("month", CheckIn.timestamp) == month,
        )
        .order_by(CheckIn.timestamp)
        .all()
    )

    people_by_day: dict[str, dict[int, dict]] = defaultdict(dict)
    for checkin, employee in rows:
        day = checkin.timestamp.strftime("%Y-%m-%d")
        person = people_by_day[day].setdefault(
            employee.id,
            {
                "employee_id": employee.id,
                "employee_code": employee.employee_code,
                "full_name": employee.full_name,
                "first_in": None,
                "last_out": None,
                "locations": [],
                "count": 0,
            },
        )
        person["count"] += 1
        timestamp = checkin.timestamp.isoformat()
        if checkin.kind == "in" and (
            person["first_in"] is None or timestamp < person["first_in"]
        ):
            person["first_in"] = timestamp
        elif checkin.kind == "out" and (
            person["last_out"] is None or timestamp > person["last_out"]
        ):
            person["last_out"] = timestamp

        location = _location_label(checkin.office_name, checkin.within_geofence)
        if location not in person["locations"]:
            person["locations"].append(location)

    days = [
        {
            "date": day,
            "people": sorted(people.values(), key=lambda item: item["full_name"]),
        }
        for day, people in sorted(people_by_day.items())
    ]
    return {"year": year, "month": month, "days": days}
