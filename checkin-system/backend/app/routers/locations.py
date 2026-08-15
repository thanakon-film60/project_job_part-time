from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..database import get_db
from ..geofence import evaluate_location
from ..models import Employee, LocationPing
from ..schemas import LocationPingIn, LocationPingOut
from ..security import get_current_employee

router = APIRouter(prefix="/locations", tags=["locations"])


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
