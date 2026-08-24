from datetime import datetime

from pydantic import BaseModel, EmailStr


class EmployeeCreate(BaseModel):
    employee_code: str
    full_name: str
    email: EmailStr
    password: str
    is_manager: bool = False


class EmployeeOut(BaseModel):
    id: int
    employee_code: str
    full_name: str
    email: EmailStr
    is_manager: bool
    created_at: datetime

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    employee: EmployeeOut


class CheckInOut(BaseModel):
    id: int
    employee_id: int
    kind: str
    timestamp: datetime
    latitude: float
    longitude: float
    distance_km: float
    within_geofence: bool
    office_name: str | None = None
    face_detected: bool
    photo_path: str | None

    class Config:
        from_attributes = True


class LocationPingIn(BaseModel):
    latitude: float
    longitude: float


class LocationPingOut(BaseModel):
    id: int
    employee_id: int
    timestamp: datetime
    latitude: float
    longitude: float
    distance_km: float
    within_geofence: bool
    office_name: str | None = None

    class Config:
        from_attributes = True


class LiveLocationOut(BaseModel):
    """ตำแหน่งล่าสุดของพนักงานหนึ่งคน สำหรับหน้าแผนที่ของหัวหน้า

    พนักงานที่ยังไม่เคยส่งพิกัดมาเลยก็จะอยู่ในรายการนี้ด้วย (status="no_data")
    เพื่อให้หัวหน้าเห็นว่ามีใครที่แอปยังไม่ส่งตำแหน่งบ้าง
    """

    employee_id: int
    employee_code: str
    full_name: str
    is_manager: bool

    latitude: float | None = None
    longitude: float | None = None
    distance_km: float | None = None
    within_geofence: bool | None = None
    office_name: str | None = None

    timestamp: datetime | None = None
    # อายุของพิกัดคิดจากฝั่งเซิร์ฟเวอร์ ป้องกันปัญหา timezone ของเครื่อง client
    seconds_ago: int | None = None
    # online = สดใหม่ / stale = เก่าแล้ว / offline = นานมาก / no_data = ไม่เคยส่ง
    status: str


class LiveLocationsResponse(BaseModel):
    server_time: datetime
    online_threshold_seconds: int
    stale_threshold_seconds: int
    employees: list[LiveLocationOut]


class TrailPointOut(BaseModel):
    timestamp: datetime
    latitude: float
    longitude: float
    within_geofence: bool
    office_name: str | None = None

    class Config:
        from_attributes = True


class FaceProfileOut(BaseModel):
    id: int
    employee_id: int
    source: str
    note: str | None
    created_at: datetime

    class Config:
        from_attributes = True


class OfficeInfo(BaseModel):
    """สถานที่ที่เช็คอินได้ 1 แห่ง"""

    name: str
    lat: float
    lng: float
    radius_km: float
    allow_checkout: bool = True
    category: str | None = None


class GeofenceInfo(BaseModel):
    # รายการสถานที่ทั้งหมด (รองรับหลายสาขา)
    offices: list[OfficeInfo] = []

    # ---- ฟิลด์เดิม: ชี้ไปที่สถานที่แรกในรายการ ----
    # เก็บไว้เพื่อให้เว็บ/แอปเวอร์ชันเก่ายังใช้งานได้
    office_name: str
    office_lat: float
    office_lng: float
    radius_km: float
