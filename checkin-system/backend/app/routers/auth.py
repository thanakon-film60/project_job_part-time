from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Employee
from ..schemas import EmployeeCreate, EmployeeOut, Token
from ..security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=EmployeeOut)
def register(payload: EmployeeCreate, db: Session = Depends(get_db)):
    exists = (
        db.query(Employee)
        .filter(
            (Employee.email == payload.email)
            | (Employee.employee_code == payload.employee_code)
        )
        .first()
    )
    if exists:
        raise HTTPException(status_code=400, detail="อีเมลหรือรหัสพนักงานนี้มีอยู่แล้ว")

    emp = Employee(
        employee_code=payload.employee_code,
        full_name=payload.full_name,
        email=payload.email,
        hashed_password=hash_password(payload.password),
        is_manager=payload.is_manager,
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)
    return emp


@router.post("/login", response_model=Token)
def login(
    form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)
):
    # username field = employee_code หรือ email
    emp = (
        db.query(Employee)
        .filter(
            (Employee.employee_code == form.username)
            | (Employee.email == form.username)
        )
        .first()
    )
    if not emp or not verify_password(form.password, emp.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="รหัสพนักงานหรือรหัสผ่านไม่ถูกต้อง",
        )
    token = create_access_token(emp.employee_code)
    return Token(access_token=token, employee=emp)
