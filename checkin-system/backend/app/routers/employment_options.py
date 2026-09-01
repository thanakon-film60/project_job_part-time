from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Employee, EmploymentOption
from ..schemas import EmploymentOptionCreate, EmploymentOptionOut
from ..security import require_manager

router = APIRouter(prefix="/employment-options", tags=["employment-options"])

DEFAULT_OPTIONS = {
    "department": ["ฝ่ายปฏิบัติการ", "ฝ่ายบุคคล", "ฝ่ายบัญชี", "ฝ่ายขาย"],
    "position": ["เจ้าหน้าที่ประสานงาน", "พนักงานพาร์ตไทม์", "หัวหน้าทีม", "ผู้จัดการ"],
}


def _ensure_defaults(db: Session) -> None:
    if db.query(EmploymentOption.id).first():
        return
    for kind, names in DEFAULT_OPTIONS.items():
        db.add_all(EmploymentOption(kind=kind, name=name) for name in names)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()


@router.get("", response_model=list[EmploymentOptionOut])
def list_employment_options(
    _: Employee = Depends(require_manager), db: Session = Depends(get_db)
):
    _ensure_defaults(db)
    return (
        db.query(EmploymentOption)
        .order_by(EmploymentOption.kind, EmploymentOption.name)
        .all()
    )


@router.post("", response_model=EmploymentOptionOut, status_code=status.HTTP_201_CREATED)
def create_employment_option(
    payload: EmploymentOptionCreate,
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    option = EmploymentOption(kind=payload.kind, name=payload.name)
    db.add(option)
    try:
        db.commit()
        db.refresh(option)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="มีตัวเลือกนี้อยู่แล้ว")
    return option
