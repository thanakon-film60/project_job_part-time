import base64
import hashlib
import hmac
from datetime import datetime, timedelta

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from cryptography.fernet import Fernet
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models import Employee

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


def _personal_data_cipher() -> Fernet:
    key = base64.urlsafe_b64encode(hashlib.sha256(settings.secret_key.encode()).digest())
    return Fernet(key)


def encrypt_personal_data(value: str) -> str:
    return _personal_data_cipher().encrypt(value.encode()).decode()


def decrypt_personal_data(value: str) -> str:
    return _personal_data_cipher().decrypt(value.encode()).decode()


def personal_data_hash(value: str) -> str:
    return hmac.new(settings.secret_key.encode(), value.encode(), hashlib.sha256).hexdigest()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(subject: str) -> str:
    expire = datetime.utcnow() + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {"sub": subject, "exp": expire}
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def get_current_employee(
    token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> Employee:
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="ไม่สามารถยืนยันตัวตนได้",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            token, settings.secret_key, algorithms=[settings.algorithm]
        )
        code = payload.get("sub")
        if code is None:
            raise credentials_exc
    except JWTError:
        raise credentials_exc

    emp = db.query(Employee).filter(Employee.employee_code == code).first()
    if emp is None:
        raise credentials_exc
    return emp


def require_manager(emp: Employee = Depends(get_current_employee)) -> Employee:
    if not emp.is_manager:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="ต้องเป็นผู้จัดการเท่านั้น",
        )
    return emp
