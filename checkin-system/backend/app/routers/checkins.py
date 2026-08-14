import os
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..geofence import evaluate_location
from ..models import CheckIn, Employee
from ..schemas import CheckInOut
from ..security import get_current_employee

router = APIRouter(prefix="/checkins", tags=["checkins"])


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

    distance_km, within = evaluate_location(latitude, longitude)

    # เงื่อนไข: ต้องอยู่ในรัศมี และต้องตรวจพบใบหน้า
    if not within:
        raise HTTPException(
            status_code=422,
            detail=f"อยู่นอกเขตออฟฟิศ ({distance_km:.2f} กม. > "
            f"{settings.geofence_radius_km} กม.) เช็คอินไม่ได้",
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
        face_detected=face_detected,
        photo_path=photo_path,
    )
    db.add(record)
    db.commit()
    db.refresh(record)
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
