from cryptography.fernet import InvalidToken

from .models import Employee
from .schemas import EmployeeProfileOut
from .security import decrypt_personal_data


PROFILE_FIELDS = (
    "birth_date",
    "national_id_encrypted",
    "phone",
    "address_line",
    "postal_code",
    "subdistrict",
    "district",
    "province",
    "department",
    "position",
    "start_date",
)


def _masked_national_id(employee: Employee) -> str | None:
    if not employee.national_id_encrypted:
        return None
    try:
        value = decrypt_personal_data(employee.national_id_encrypted)
    except (InvalidToken, ValueError):
        return "*************"
    return f"*********{value[-4:]}"


def employee_profile(employee: Employee) -> EmployeeProfileOut:
    return EmployeeProfileOut(
        id=employee.id,
        employee_code=employee.employee_code,
        full_name=employee.full_name,
        email=employee.email,
        is_manager=employee.is_manager,
        created_at=employee.created_at,
        updated_at=employee.updated_at,
        birth_date=employee.birth_date,
        national_id_masked=_masked_national_id(employee),
        phone=employee.phone,
        address_line=employee.address_line,
        postal_code=employee.postal_code,
        subdistrict=employee.subdistrict,
        district=employee.district,
        province=employee.province,
        department=employee.department,
        position=employee.position,
        start_date=employee.start_date,
        profile_complete=all(getattr(employee, field, None) for field in PROFILE_FIELDS),
    )
