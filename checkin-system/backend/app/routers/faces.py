import os
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import Employee, FaceProfile
from ..schemas import FaceProfileOut
from ..security import get_current_employee

router = APIRouter(prefix="/faces", tags=["faces"])

FACE_DIR = os.path.join(settings.storage_dir, "faces")


@router.post("/enroll", response_model=FaceProfileOut)
async def enroll_face(
    photo: UploadFile = File(...),
    source: str = Form("web"),
    note: str | None = Form(None),
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """บันทึกรูปใบหน้าเข้าประวัติของพนักงานคนที่ล็อกอินอยู่"""
    os.makedirs(FACE_DIR, exist_ok=True)
    ext = os.path.splitext(photo.filename or "")[1] or ".jpg"
    fname = f"{emp.employee_code}_{uuid.uuid4().hex}{ext}"
    full = os.path.join(FACE_DIR, fname)
    with open(full, "wb") as f:
        f.write(await photo.read())

    record = FaceProfile(
        employee_id=emp.id, photo_path=full, source=source, note=note
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


@router.get("/me", response_model=list[FaceProfileOut])
def my_faces(
    emp: Employee = Depends(get_current_employee), db: Session = Depends(get_db)
):
    return (
        db.query(FaceProfile)
        .filter(FaceProfile.employee_id == emp.id)
        .order_by(FaceProfile.created_at.desc())
        .all()
    )


@router.get("/employee/{employee_id}", response_model=list[FaceProfileOut])
def employee_faces(
    employee_id: int,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    # ผู้จัดการดูได้ทุกคน / พนักงานดูได้เฉพาะของตัวเอง
    if not emp.is_manager and emp.id != employee_id:
        raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์ดูข้อมูลนี้")
    return (
        db.query(FaceProfile)
        .filter(FaceProfile.employee_id == employee_id)
        .order_by(FaceProfile.created_at.desc())
        .all()
    )


@router.get("/{record_id}/photo")
def face_photo(
    record_id: int,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """สตรีมไฟล์รูป (เฉพาะเจ้าของหรือผู้จัดการ)"""
    rec = db.query(FaceProfile).filter(FaceProfile.id == record_id).first()
    if not rec:
        raise HTTPException(status_code=404, detail="ไม่พบรูป")
    if not emp.is_manager and emp.id != rec.employee_id:
        raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์ดูรูปนี้")
    if not os.path.exists(rec.photo_path):
        raise HTTPException(status_code=404, detail="ไฟล์รูปหาย")
    return FileResponse(rec.photo_path)
