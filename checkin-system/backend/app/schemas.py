from datetime import date, datetime

from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator


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


class ThaiAddressOut(BaseModel):
    id: int
    postal_code: str
    subdistrict: str
    district: str
    province: str


class EmploymentOptionCreate(BaseModel):
    kind: Literal["department", "position"]
    name: str = Field(min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if not value:
            raise ValueError("กรุณากรอกชื่อตัวเลือก")
        return value


class EmploymentOptionOut(BaseModel):
    id: int
    kind: str
    name: str

    class Config:
        from_attributes = True


def _valid_thai_id(value: str) -> bool:
    if len(value) != 13 or not value.isdigit() or len(set(value)) == 1:
        return False
    total = sum(int(digit) * (13 - index) for index, digit in enumerate(value[:12]))
    return (11 - total % 11) % 10 == int(value[12])


class PersonalInfoIn(BaseModel):
    firstName: str = Field(min_length=1, max_length=100)
    lastName: str = Field(min_length=1, max_length=100)
    birthDate: date
    nationalId: str = Field(pattern=r"^\d{13}$")

    @field_validator("nationalId")
    @classmethod
    def validate_national_id(cls, value: str) -> str:
        if not _valid_thai_id(value):
            raise ValueError("เลขบัตรประชาชนไม่ผ่านการตรวจสอบ")
        return value


class AddressIn(BaseModel):
    addressLine: str = Field(min_length=1, max_length=255)
    subdistrict: str = Field(min_length=1, max_length=120)
    district: str = Field(min_length=1, max_length=120)
    province: str = Field(min_length=1, max_length=120)
    postalCode: str = Field(pattern=r"^\d{5}$")


class ContactInfoIn(BaseModel):
    phone: str = Field(pattern=r"^0\d{8,9}$")
    email: EmailStr
    address: AddressIn


class EmploymentInfoIn(BaseModel):
    department: str = Field(min_length=1, max_length=120)
    position: str = Field(min_length=1, max_length=120)
    startDate: date


class EmployeeRegistrationIn(BaseModel):
    personalInfo: PersonalInfoIn
    contact: ContactInfoIn
    employment: EmploymentInfoIn


class EmployeeProfileUpdateIn(BaseModel):
    fullName: str | None = Field(default=None, min_length=1, max_length=201)
    birthDate: date | None = None
    nationalId: str | None = Field(default=None, pattern=r"^\d{13}$")
    phone: str | None = Field(default=None, pattern=r"^0\d{8,9}$")
    email: EmailStr | None = None
    addressLine: str | None = Field(default=None, min_length=1, max_length=255)
    postalCode: str | None = Field(default=None, pattern=r"^\d{5}$")
    subdistrict: str | None = Field(default=None, min_length=1, max_length=120)
    district: str | None = Field(default=None, min_length=1, max_length=120)
    province: str | None = Field(default=None, min_length=1, max_length=120)
    department: str | None = Field(default=None, min_length=1, max_length=120)
    position: str | None = Field(default=None, min_length=1, max_length=120)
    startDate: date | None = None

    @field_validator("fullName", "addressLine", "department", "position")
    @classmethod
    def clean_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = " ".join(value.split())
        if not cleaned:
            raise ValueError("กรุณากรอกข้อมูล")
        return cleaned

    @field_validator("nationalId")
    @classmethod
    def validate_national_id(cls, value: str | None) -> str | None:
        if value is not None and not _valid_thai_id(value):
            raise ValueError("เลขบัตรประชาชนไม่ผ่านการตรวจสอบ")
        return value


class EmployeeProfileOut(BaseModel):
    id: int
    employee_code: str
    full_name: str
    email: EmailStr
    is_manager: bool
    created_at: datetime
    updated_at: datetime | None = None
    birth_date: date | None = None
    national_id_masked: str | None = None
    phone: str | None = None
    address_line: str | None = None
    postal_code: str | None = None
    subdistrict: str | None = None
    district: str | None = None
    province: str | None = None
    department: str | None = None
    position: str | None = None
    start_date: date | None = None
    profile_complete: bool


class EmployeeRegistrationOut(BaseModel):
    employee: EmployeeProfileOut
    temporary_password: str


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
    # ลำดับที่พนักงานจัดเอง — None = ยังไม่เคยจัด (เรียงตามเวลาบันทึก)
    sort_order: int | None = None

    class Config:
        from_attributes = True


class FaceOrderIn(BaseModel):
    """ลำดับรูปใบหน้าใหม่ที่พนักงานลากจัดเอง

    ส่ง id ของ "ทุกรูปของตัวเอง" มาเรียงตามลำดับที่ต้องการ รูปแรกในลิสต์
    (ลำดับ 0) จะถูกใช้เป็นรูปประจำตัวทุกที่ที่ระบบแสดงรูปพนักงาน
    """

    face_ids: list[int] = Field(min_length=1)


class EmployeeEventOut(BaseModel):
    id: int
    event_type: str
    title: str
    detail: dict | None
    created_at: datetime

    class Config:
        from_attributes = True


class EmployeeHistoryOut(BaseModel):
    employee: EmployeeProfileOut
    year: int
    month: int
    checkins: list[CheckInOut]
    face_profiles: list[FaceProfileOut]
    events: list[EmployeeEventOut]


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


# ---------------------------------------------------------------------
# กล้องวงจรปิด ONVIF
# ---------------------------------------------------------------------

# ทิศที่สั่งได้ — ตรงกับปุ่มบนหน้าจอ
# home = กลับตำแหน่งตั้งต้น (ปุ่ม Reset), stop = สั่งหยุดทันที
CameraPtzAction = Literal[
    "up", "down", "left", "right", "zoom_in", "zoom_out", "home", "stop"
]


class CameraPtzIn(BaseModel):
    action: CameraPtzAction

    # หมุนนานกี่มิลลิวินาทีแล้วหยุดเอง — ไม่ส่งมาก็ใช้ค่าจาก .env
    # เพดานถูกบังคับอีกชั้นที่ router ด้วย CAMERA_PTZ_MAX_DURATION_MS
    duration_ms: int | None = Field(default=None, ge=100, le=10000)


class CameraPtzOut(BaseModel):
    ok: bool
    action: str
    message: str


class CameraStatusOut(BaseModel):
    """สถานะกล้อง — แอปเอาไปตัดสินว่าจะโชว์ปุ่มควบคุมหรือขึ้นข้อความว่าต่อไม่ได้"""

    enabled: bool
    reachable: bool
    host: str
    message: str
    model: str | None = None
    firmware: str | None = None
    home_supported: bool = False

    # ฟังเสียงจากไมค์กล้องได้ไหม (เซิร์ฟเวอร์ต้องมี ffmpeg ด้วย)
    audio_supported: bool = False

    # ทำไมถึงฟังเสียงไม่ได้ — ให้แอปบอกผู้ใช้ได้ตรงจุดว่าติดที่อะไร
    # (null เมื่อฟังได้ปกติ)
    audio_note: str | None = None

    # พูดกลับออกลำโพงกล้องได้ไหม
    #
    # ไม่ได้เขียนคำตอบตายตัวไว้แล้ว — เซิร์ฟเวอร์ไปถามกล้องจริงทุกครั้ง
    # (RTSP DESCRIBE + Require backchannel) กล้องรุ่นที่รองรับจะเปิดปุ่มเอง
    talkback_supported: bool = False

    # ทำไมถึงพูดกลับไม่ได้ — เอาไว้แสดงให้ผู้ใช้เห็นว่าติดที่กล้องไม่ใช่ที่แอป
    talkback_note: str | None = None

    # พร้อมให้แอปของเราเริ่มพูดจริงหรือยัง ต่างจาก talkback_supported ที่บอก
    # เพียงว่ากล้อง/โปรโตคอลมีความสามารถรับเสียง
    talkback_ready: bool = False
    talkback_transport: Literal["tirtc"] | None = None
    talkback_token_path: str | None = None
    talkback_stream_id: int | None = None


class CameraTalkbackTokenOut(BaseModel):
    """ข้อมูลชั่วคราวที่ Flutter ต้องใช้เปิด TiRTC connection ไปยังกล้อง"""

    provider: Literal["tirtc"] = "tirtc"
    app_id: str
    remote_id: str
    token: str
    issued_at: int
    expires_at: int
    stream_id: int
    audio_codec: Literal["g711a"] = "g711a"
    sample_rate_hz: Literal[16000] = 16000
    channels: Literal[1] = 1
