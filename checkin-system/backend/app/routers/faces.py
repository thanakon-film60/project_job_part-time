import logging
import os
import shutil
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import Employee, FaceProfile
from ..schemas import FaceOrderIn, FaceProfileOut
from ..security import get_current_employee

router = APIRouter(prefix="/faces", tags=["faces"])
log = logging.getLogger("faces")

FACE_DIR = os.path.join(settings.storage_dir, "faces")


def ordered_faces(db: Session, employee_id: int) -> list[FaceProfile]:
    """รูปใบหน้าของพนักงานคนหนึ่ง เรียงตามลำดับที่เจ้าตัวจัดไว้

    รูปแรกในลิสต์ถูกใช้เป็น "รูปประจำตัว" ทุกที่ที่ระบบแสดงรูปพนักงาน
    (แอปมือถือ หน้ารายชื่อ หน้าแฟ้มพนักงาน) พนักงานจึงเลือกได้เองว่าจะใช้รูปไหน
    ด้วยการลากรูปนั้นไปไว้อันแรก

    รูปที่ยังไม่เคยถูกจัดลำดับ (sort_order = NULL) จะต่อท้ายโดยเรียงตามเวลา
    บันทึกใหม่สุดขึ้นก่อน — พฤติกรรมเดิมก่อนมีฟีเจอร์นี้

    เรียงในฝั่ง Python ไม่ใช่ใน SQL เพราะ SQLite กับ PostgreSQL จัดตำแหน่ง
    ของ NULL ใน ORDER BY ไม่เหมือนกัน (NULLS FIRST/LAST) และรูปต่อคนมีไม่กี่ใบ
    """
    rows = db.query(FaceProfile).filter(FaceProfile.employee_id == employee_id).all()
    rows.sort(
        key=lambda row: (
            row.sort_order is None,
            row.sort_order if row.sort_order is not None else 0,
            -row.created_at.timestamp(),
        )
    )
    return rows


def _remove_photo_file(path: str | None) -> None:
    """ลบไฟล์รูปออกจากดิสก์ — ไฟล์หายไปแล้วก็ไม่เป็นไร

    ห้าม raise ออกไป ไม่งั้นการลบแถวใน DB จะล้มเพราะไฟล์ที่หายไปตั้งแต่แรก
    แล้วผู้ใช้จะลบรูปนั้นทิ้งไม่ได้เลยตลอดกาล
    """
    if not path:
        return
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
    except OSError as e:
        log.warning("ลบไฟล์รูปไม่สำเร็จ (%s): %s", path, e)


@router.post("/enroll", response_model=FaceProfileOut)
def enroll_face(
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
    # Endpoint เป็น sync เพื่อให้ FastAPI รันทั้ง file I/O และ SQLAlchemy
    # ใน thread pool และคัดลอกเป็น stream โดยไม่โหลดรูปทั้งหมดเข้า RAM
    with open(full, "wb") as f:
        shutil.copyfileobj(photo.file, f)

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
    return ordered_faces(db, emp.id)


@router.get("/employee/{employee_id}", response_model=list[FaceProfileOut])
def employee_faces(
    employee_id: int,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    # ผู้จัดการดูได้ทุกคน / พนักงานดูได้เฉพาะของตัวเอง
    if not emp.is_manager and emp.id != employee_id:
        raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์ดูข้อมูลนี้")
    return ordered_faces(db, employee_id)


@router.put("/order", response_model=list[FaceProfileOut])
def reorder_faces(
    payload: FaceOrderIn,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """จัดลำดับรูปใบหน้าของตัวเองใหม่ (ลากสลับในแอป)

    จัดได้เฉพาะรูปของตัวเอง — หัวหน้าก็จัดของคนอื่นไม่ได้ เพราะนี่คือการเลือก
    รูปประจำตัวของเจ้าตัว ไม่ใช่ข้อมูลการลงเวลาที่ต้องมีคนตรวจ

    ต้องส่ง id ของรูป "ทุกใบ" ที่มีอยู่มาพร้อมกัน จะได้ไม่เหลือรูปที่ลำดับค้าง
    อยู่ครึ่ง ๆ กลาง ๆ แล้วตำแหน่งเพี้ยนในการจัดครั้งถัดไป
    """
    rows = db.query(FaceProfile).filter(FaceProfile.employee_id == emp.id).all()
    by_id = {row.id: row for row in rows}

    seen: set[int] = set()
    for face_id in payload.face_ids:
        if face_id not in by_id:
            raise HTTPException(
                status_code=404, detail="มีรูปที่ไม่ใช่ของคุณหรือถูกลบไปแล้วอยู่ในรายการ"
            )
        if face_id in seen:
            raise HTTPException(status_code=400, detail="มี id ซ้ำในรายการ")
        seen.add(face_id)

    if len(seen) != len(rows):
        raise HTTPException(
            status_code=400,
            detail=f"ต้องส่งรูปให้ครบทุกใบ (มีอยู่ {len(rows)} ใบ ส่งมา {len(seen)} ใบ)",
        )

    for position, face_id in enumerate(payload.face_ids):
        by_id[face_id].sort_order = position
    db.commit()

    return ordered_faces(db, emp.id)


@router.delete("/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_face(
    record_id: int,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ลบรูปใบหน้าอ้างอิงทิ้ง (เจ้าของหรือผู้จัดการ)

    ลบได้เฉพาะรูป "อ้างอิง" ที่พนักงานถ่ายเก็บไว้เอง — ไม่แตะรูปที่แนบมากับ
    การลงเวลาแต่ละครั้ง (checkins.photo_path) ซึ่งเป็นหลักฐานการเข้างาน
    และเก็บอยู่คนละตาราง
    """
    rec = db.query(FaceProfile).filter(FaceProfile.id == record_id).first()
    if not rec:
        raise HTTPException(status_code=404, detail="ไม่พบรูป")
    if not emp.is_manager and emp.id != rec.employee_id:
        raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์ลบรูปนี้")

    employee_id = rec.employee_id
    photo_path = rec.photo_path

    db.delete(rec)
    db.commit()

    # ไล่ลำดับใหม่ให้ต่อเนื่อง (0,1,2,...) เฉพาะรูปที่เคยจัดลำดับไว้แล้ว
    # ไม่งั้นการลบรูปกลางจะทิ้งช่องว่างไว้ในลำดับ
    remaining = [
        row
        for row in ordered_faces(db, employee_id)
        if row.sort_order is not None
    ]
    for position, row in enumerate(remaining):
        row.sort_order = position
    if remaining:
        db.commit()

    # ลบไฟล์หลังจาก DB สำเร็จแล้ว — ถ้าทำสลับกันแล้ว commit ล้ม
    # จะเหลือแถวที่ชี้ไปยังไฟล์ที่ไม่มีอยู่จริง
    _remove_photo_file(photo_path)


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
