from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, func
from sqlalchemy.orm import Session

from ..database import get_db
from ..geofence import evaluate_location
from ..models import Employee, LocationPing
from ..schemas import (
    LiveLocationOut,
    LiveLocationsResponse,
    LocationPingIn,
    LocationPingOut,
    TrailPointOut,
)
from ..security import get_current_employee, require_manager

router = APIRouter(prefix="/locations", tags=["locations"])

# เกณฑ์ตัดสินว่าพิกัดที่ได้มา "สด" แค่ไหน (วินาที)
# แอป Flutter ส่ง ping มาเป็นระยะ ถ้าเงียบไปนานกว่านี้แปลว่าปิดแอป/เน็ตหลุด/ปิด GPS
ONLINE_THRESHOLD_SECONDS = 5 * 60
STALE_THRESHOLD_SECONDS = 30 * 60


@router.post("/ping", response_model=LocationPingOut)
def ping(
    payload: LocationPingIn,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """Flutter ส่งพิกัด GPS มาต่อเนื่อง (background) เพื่อบันทึกว่าอยู่ในเขตหรือไม่"""
    distance_km, within, office = evaluate_location(payload.latitude, payload.longitude)
    ping = LocationPing(
        employee_id=emp.id,
        timestamp=datetime.utcnow(),
        latitude=payload.latitude,
        longitude=payload.longitude,
        distance_km=distance_km,
        within_geofence=within,
        office_name=office["name"],
    )
    db.add(ping)
    db.commit()
    db.refresh(ping)
    return ping


def _status_from_age(seconds_ago: int | None) -> str:
    if seconds_ago is None:
        return "no_data"
    if seconds_ago <= ONLINE_THRESHOLD_SECONDS:
        return "online"
    if seconds_ago <= STALE_THRESHOLD_SECONDS:
        return "stale"
    return "offline"


@router.get("/live", response_model=LiveLocationsResponse)
def live_locations(
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """ตำแหน่งล่าสุดของพนักงานทุกคน — ใช้กับหน้าแผนที่ของหัวหน้า

    เริ่มจากรายชื่อพนักงานทั้งหมดก่อน แล้วค่อยเติมพิกัดล่าสุดให้ ดังนั้นคน
    ที่แอปยังไม่เคยส่งพิกัดมาก็จะยังโผล่ในรายการ (status="no_data") ไม่ใช่
    หายไปเงียบๆ ซึ่งเป็นข้อมูลที่หัวหน้าต้องรู้พอๆ กับตำแหน่งของคนที่ส่งมา
    """
    now = datetime.utcnow()

    # หา timestamp ล่าสุดของแต่ละคนก่อน แล้ว join กลับไปเอาทั้งแถว
    # (เขียนแบบนี้เพื่อให้ใช้ได้ทั้ง SQLite และ Postgres)
    latest_ts = (
        db.query(
            LocationPing.employee_id.label("employee_id"),
            func.max(LocationPing.timestamp).label("max_ts"),
        )
        .group_by(LocationPing.employee_id)
        .subquery()
    )

    latest_rows = (
        db.query(LocationPing)
        .join(
            latest_ts,
            and_(
                LocationPing.employee_id == latest_ts.c.employee_id,
                LocationPing.timestamp == latest_ts.c.max_ts,
            ),
        )
        .all()
    )

    # ถ้ามีสอง ping ที่ timestamp เท่ากันเป๊ะ ให้ยึดอันที่ id สูงกว่า (ใหม่กว่า)
    latest_by_emp: dict[int, LocationPing] = {}
    for row in latest_rows:
        current = latest_by_emp.get(row.employee_id)
        if current is None or row.id > current.id:
            latest_by_emp[row.employee_id] = row

    employees = db.query(Employee).order_by(Employee.full_name).all()

    result: list[LiveLocationOut] = []
    for emp in employees:
        ping_row = latest_by_emp.get(emp.id)
        if ping_row is None:
            result.append(
                LiveLocationOut(
                    employee_id=emp.id,
                    employee_code=emp.employee_code,
                    full_name=emp.full_name,
                    is_manager=emp.is_manager,
                    status="no_data",
                )
            )
            continue

        seconds_ago = max(0, int((now - ping_row.timestamp).total_seconds()))
        result.append(
            LiveLocationOut(
                employee_id=emp.id,
                employee_code=emp.employee_code,
                full_name=emp.full_name,
                is_manager=emp.is_manager,
                latitude=ping_row.latitude,
                longitude=ping_row.longitude,
                distance_km=ping_row.distance_km,
                within_geofence=ping_row.within_geofence,
                office_name=ping_row.office_name,
                timestamp=ping_row.timestamp,
                seconds_ago=seconds_ago,
                status=_status_from_age(seconds_ago),
            )
        )

    # เรียงให้คนที่ยังส่งพิกัดอยู่ขึ้นก่อน แล้วค่อยไล่ตามชื่อ
    status_order = {"online": 0, "stale": 1, "offline": 2, "no_data": 3}
    result.sort(key=lambda r: (status_order.get(r.status, 9), r.full_name))

    return LiveLocationsResponse(
        server_time=now,
        online_threshold_seconds=ONLINE_THRESHOLD_SECONDS,
        stale_threshold_seconds=STALE_THRESHOLD_SECONDS,
        employees=result,
    )


@router.get("/trail/{employee_id}", response_model=list[TrailPointOut])
def location_trail(
    employee_id: int,
    hours: int = Query(6, ge=1, le=72),
    limit: int = Query(500, ge=10, le=5000),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """เส้นทางย้อนหลังของพนักงานหนึ่งคน — ใช้วาดเส้นทางบนแผนที่

    จำกัดจำนวนจุดไว้ (limit) เพราะ ping ที่ส่งมาทุกไม่กี่นาทีสะสมได้เร็วมาก
    ถ้าดึงทั้งหมดแผนที่จะช้าจนใช้งานไม่ได้
    """
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if emp is None:
        raise HTTPException(status_code=404, detail="ไม่พบพนักงานคนนี้")

    since = datetime.utcnow() - timedelta(hours=hours)

    # ดึงจุดล่าสุดมา limit จุด แล้วค่อยกลับด้านให้เรียงตามเวลา (เก่า -> ใหม่)
    rows = (
        db.query(LocationPing)
        .filter(
            LocationPing.employee_id == employee_id,
            LocationPing.timestamp >= since,
        )
        .order_by(LocationPing.timestamp.desc())
        .limit(limit)
        .all()
    )
    rows.reverse()
    return rows
