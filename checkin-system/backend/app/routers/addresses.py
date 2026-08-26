import json
from collections import defaultdict
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter, Depends, Path as ApiPath

from ..models import Employee
from ..schemas import ThaiAddressOut
from ..security import require_manager

router = APIRouter(prefix="/addresses", tags=["addresses"])

DATA_FILE = Path(__file__).resolve().parent.parent / "data" / "thai_addresses.json"


@lru_cache(maxsize=1)
def _addresses_by_postal_code() -> dict[str, list[ThaiAddressOut]]:
    """อ่านไฟล์ครั้งเดียว แล้วสร้าง index เพื่อให้ทุก request หลังจากนั้นค้นหา O(1)."""
    with DATA_FILE.open(encoding="utf-8") as file:
        rows = json.load(file)

    index: dict[str, list[ThaiAddressOut]] = defaultdict(list)
    for row in rows:
        district = row.get("district") or {}
        province = district.get("province") or {}
        if row.get("deleted_at") or district.get("deleted_at") or province.get("deleted_at"):
            continue

        postal_code = str(row.get("zip_code", ""))
        if len(postal_code) != 5:
            continue

        index[postal_code].append(
            ThaiAddressOut(
                id=row["id"],
                postal_code=postal_code,
                subdistrict=row["name_th"],
                district=district["name_th"],
                province=province["name_th"],
            )
        )

    return dict(index)


@router.get("/postal-code/{postal_code}", response_model=list[ThaiAddressOut])
def addresses_by_postal_code(
    postal_code: str = ApiPath(pattern=r"^\d{5}$"),
    _: Employee = Depends(require_manager),
):
    return _addresses_by_postal_code().get(postal_code, [])

