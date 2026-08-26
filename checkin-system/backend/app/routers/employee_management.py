import re
import secrets
import string
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..employee_profiles import employee_profile
from ..models import Employee, EmployeeEvent, EmploymentOption
from ..schemas import (
    EmployeeProfileOut,
    EmployeeProfileUpdateIn,
    EmployeeRegistrationIn,
    EmployeeRegistrationOut,
)
from ..security import (
    encrypt_personal_data,
    hash_password,
    personal_data_hash,
    require_manager,
)
from .addresses import _addresses_by_postal_code

router = APIRouter(prefix="/employee-management", tags=["employee-management"])


PROFILE_FIELD_MAP = {
    "fullName": ("full_name", "ชื่อ-นามสกุล"),
    "birthDate": ("birth_date", "วันเกิด"),
    "phone": ("phone", "เบอร์โทร"),
    "email": ("email", "อีเมล"),
    "addressLine": ("address_line", "ที่อยู่"),
    "postalCode": ("postal_code", "รหัสไปรษณีย์"),
    "subdistrict": ("subdistrict", "ตำบล/แขวง"),
    "district": ("district", "อำเภอ/เขต"),
    "province": ("province", "จังหวัด"),
    "department": ("department", "แผนก"),
    "position": ("position", "ตำแหน่ง"),
    "startDate": ("start_date", "วันเริ่มงาน"),
}


def _next_employee_code(db: Session) -> str:
    numbers = []
    for (code,) in db.query(Employee.employee_code).filter(Employee.employee_code.like("EMP%")).all():
        match = re.fullmatch(r"EMP(\d+)", code or "")
        if match:
            numbers.append(int(match.group(1)))
    return f"EMP{max(numbers, default=0) + 1:03d}"


def _temporary_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


@router.post("", response_model=EmployeeRegistrationOut, status_code=status.HTTP_201_CREATED)
def register_employee(
    payload: EmployeeRegistrationIn,
    manager: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    personal = payload.personalInfo
    contact = payload.contact
    address = contact.address
    employment = payload.employment
    email = str(contact.email).lower()
    national_hash = personal_data_hash(personal.nationalId)

    duplicate = (
        db.query(Employee)
        .filter((Employee.email == email) | (Employee.national_id_hash == national_hash))
        .first()
    )
    if duplicate:
        raise HTTPException(status_code=409, detail="อีเมลหรือเลขบัตรประชาชนนี้มีอยู่ในระบบแล้ว")

    address_exists = any(
        item.subdistrict == address.subdistrict
        and item.district == address.district
        and item.province == address.province
        for item in _addresses_by_postal_code().get(address.postalCode, [])
    )
    if not address_exists:
        raise HTTPException(status_code=422, detail="ข้อมูลที่อยู่ไม่ตรงกับฐานข้อมูลรหัสไปรษณีย์")

    for kind, name in (("department", employment.department), ("position", employment.position)):
        if not db.query(EmploymentOption.id).filter_by(kind=kind, name=name).first():
            raise HTTPException(status_code=422, detail=f"ไม่พบ{name}ในตัวเลือกที่ระบบกำหนด")

    temporary_password = _temporary_password()
    employee = Employee(
        employee_code=_next_employee_code(db),
        full_name=f"{personal.firstName.strip()} {personal.lastName.strip()}",
        email=email,
        hashed_password=hash_password(temporary_password),
        is_manager=False,
        birth_date=personal.birthDate,
        national_id_encrypted=encrypt_personal_data(personal.nationalId),
        national_id_hash=national_hash,
        phone=contact.phone,
        address_line=address.addressLine.strip(),
        postal_code=address.postalCode,
        subdistrict=address.subdistrict,
        district=address.district,
        province=address.province,
        department=employment.department,
        position=employment.position,
        start_date=employment.startDate,
        updated_at=datetime.utcnow(),
    )
    db.add(employee)
    db.flush()
    db.add(
        EmployeeEvent(
            employee_id=employee.id,
            actor_employee_id=manager.id,
            event_type="registered",
            title="ลงทะเบียนพนักงาน",
            detail={
                "department": employee.department,
                "position": employee.position,
                "start_date": employee.start_date.isoformat(),
            },
        )
    )
    db.commit()
    db.refresh(employee)
    return EmployeeRegistrationOut(
        employee=employee_profile(employee),
        temporary_password=temporary_password,
    )


@router.patch("/{employee_id}", response_model=EmployeeProfileOut)
def update_employee(
    employee_id: int,
    payload: EmployeeProfileUpdateIn,
    manager: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if not employee:
        raise HTTPException(status_code=404, detail="ไม่พบพนักงาน")

    changes = payload.model_dump(exclude_unset=True)
    if not changes:
        raise HTTPException(status_code=400, detail="ไม่มีข้อมูลที่ต้องการแก้ไข")

    if "email" in changes:
        changes["email"] = str(changes["email"]).lower()
        duplicate_email = db.query(Employee.id).filter(
            Employee.email == changes["email"], Employee.id != employee.id
        ).first()
        if duplicate_email:
            raise HTTPException(status_code=409, detail="อีเมลนี้มีอยู่ในระบบแล้ว")

    national_id = changes.pop("nationalId", None)
    if national_id:
        national_hash = personal_data_hash(national_id)
        duplicate_id = db.query(Employee.id).filter(
            Employee.national_id_hash == national_hash, Employee.id != employee.id
        ).first()
        if duplicate_id:
            raise HTTPException(status_code=409, detail="เลขบัตรประชาชนนี้มีอยู่ในระบบแล้ว")

    address_keys = {"postalCode", "subdistrict", "district", "province"}
    if address_keys.intersection(changes):
        postal_code = changes.get("postalCode", employee.postal_code)
        subdistrict = changes.get("subdistrict", employee.subdistrict)
        district = changes.get("district", employee.district)
        province = changes.get("province", employee.province)
        address_exists = postal_code and any(
            item.subdistrict == subdistrict
            and item.district == district
            and item.province == province
            for item in _addresses_by_postal_code().get(postal_code, [])
        )
        if not address_exists:
            raise HTTPException(status_code=422, detail="ข้อมูลที่อยู่ไม่ตรงกับฐานข้อมูลรหัสไปรษณีย์")

    for key, kind in (("department", "department"), ("position", "position")):
        if key in changes and not db.query(EmploymentOption.id).filter_by(
            kind=kind, name=changes[key]
        ).first():
            raise HTTPException(status_code=422, detail=f"ไม่พบ{changes[key]}ในตัวเลือกที่ระบบกำหนด")

    changed_fields = []
    for api_name, value in changes.items():
        model_name, label = PROFILE_FIELD_MAP[api_name]
        if getattr(employee, model_name) != value:
            setattr(employee, model_name, value)
            changed_fields.append(label)

    if national_id:
        new_hash = personal_data_hash(national_id)
        if employee.national_id_hash != new_hash:
            employee.national_id_encrypted = encrypt_personal_data(national_id)
            employee.national_id_hash = new_hash
            changed_fields.append("เลขบัตรประชาชน")

    if not changed_fields:
        return employee_profile(employee)

    employee.updated_at = datetime.utcnow()
    db.add(
        EmployeeEvent(
            employee_id=employee.id,
            actor_employee_id=manager.id,
            event_type="profile_updated",
            title="แก้ไขข้อมูลพนักงาน",
            detail={"changed_fields": changed_fields},
        )
    )
    db.commit()
    db.refresh(employee)
    return employee_profile(employee)
