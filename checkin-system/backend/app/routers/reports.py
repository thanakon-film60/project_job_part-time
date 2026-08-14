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
    return GeofenceInfo(
        office_name=settings.office_name,
        office_lat=settings.office_lat,
        office_lng=settings.office_lng,
        radius_km=settings.geofence_radius_km,
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
