import json
from datetime import date, time

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

# ใช้เมื่อ WORK_START_TIME / WORK_END_TIME ใน .env พิมพ์ผิดรูปแบบ
DEFAULT_WORK_START = time(8, 30)
DEFAULT_WORK_END = time(17, 30)


def _parse_hhmm(raw: str, fallback: time) -> time:
    """แปลง "HH:MM" เป็น time — ค่าผิดรูปแบบคืน fallback แทนที่จะทำให้ระบบล่ม

    เกณฑ์เวลาทำงานผิดไม่ควรทำให้เช็คอินทั้งระบบใช้ไม่ได้ (เหมือน offices_list
    ที่ข้าม JSON พังแล้วถอยไปใช้ค่าเริ่มต้น)
    """
    parts = (raw or "").strip().split(":")
    if len(parts) != 2:
        return fallback
    try:
        return time(int(parts[0]), int(parts[1]))
    except (TypeError, ValueError):
        return fallback


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://checkin:checkin@localhost:5432/checkin"

    # --- ออฟฟิศหลัก (ของเดิม ใช้เป็นค่า fallback ถ้าไม่ได้ตั้ง OFFICES) ---
    office_lat: float = 13.9040518
    office_lng: float = 100.5391995
    office_name: str = "Motta & Montipa (Head office)"
    geofence_radius_km: float = 0.5

    # --- รองรับหลายสถานที่ ---
    # ตั้งใน .env เป็น JSON บรรทัดเดียว เช่น
    #   OFFICES=[{"name":"Motta & Montipa (Head office)","lat":13.9040518,"lng":100.5391995,"radius_km":0.5,"category":"work"}]
    # ถ้าเว้นว่างไว้ ระบบจะใช้ office_* ด้านบนเป็นสถานที่เดียว (เข้ากันได้กับของเดิม)
    offices: str = ""

    # --- เวลาทำงานมาตรฐาน (ใช้ตัดสิน สาย / ออกก่อน) ---
    # รูปแบบ "HH:MM" ตามเวลาไทย — พิมพ์ผิดจะถอยไปใช้ค่าเริ่มต้นด้านล่าง
    # ไม่ได้เก็บลง DB: เป็นเกณฑ์ตอนคำนวณ เปลี่ยนแล้วมีผลกับข้อความแจ้งเตือนทันที
    work_start_time: str = "08:30"
    work_end_time: str = "17:30"

    # ผ่อนผันกี่นาทีถึงจะเริ่มนับว่าสาย (0 = เข้าหลัง 08:30 น. ถือว่าสายทันที)
    late_grace_minutes: int = Field(default=0, ge=0, le=180)

    # ออกก่อนเวลาเกินกี่นาทีถึงจะเตือน (0 = ออกก่อน 17:30 น. เตือนทันที)
    early_leave_grace_minutes: int = Field(default=0, ge=0, le=180)

    # ปิดการตัดสินสาย/ออกก่อนทั้งระบบ (ข้อความแจ้งเตือนจะกลับไปเป็นแบบเดิม)
    attendance_rules_enabled: bool = True

    secret_key: str = "change-this-to-a-long-random-string"
    access_token_expire_minutes: int = 720
    algorithm: str = "HS256"

    storage_dir: str = "storage"

    # --- แจ้งเตือนเข้ากลุ่ม LINE (Messaging API) ---
    # LINE Notify ปิดบริการแล้ว ต้องใช้ LINE Official Account + Messaging API
    # วิธีตั้งค่า: deploy/line/LINE_SETUP.md
    line_notify_enabled: bool = True
    line_channel_access_token: str = ""   # จาก LINE Developers Console
    line_channel_secret: str = ""         # ใช้ตรวจลายเซ็น webhook
    line_target_id: str = ""              # Group ID ของกลุ่มที่จะให้แจ้งเตือน (ขึ้นต้นด้วย C)
    # เขตเวลาที่ใช้แสดงเวลาในข้อความ (ฐานข้อมูลเก็บเป็น UTC)
    timezone_offset_hours: int = 7        # ไทย = UTC+7

    # --- รอบเงินเดือน + แจ้งเตือนรายได้เข้า LINE ---
    #
    # รอบของบริษัทนี้ไม่ตรงกับเดือนปฏิทิน: ตัดรอบวันที่ 26, รอบใหม่เริ่ม 27,
    # จ่ายเงินวันที่ 28 (เงินที่จ่ายวันที่ 28 เป็นของรอบที่ตัดไปเมื่อวันที่ 26)
    payroll_enabled: bool = True
    payroll_cutoff_day: int = Field(default=26, ge=1, le=31)
    payroll_payday: int = Field(default=28, ge=1, le=31)

    # เงินเดือนสำหรับพนักงานที่ยังไม่ได้ตั้งค่ารายคนใน employees.base_salary
    # 0 = ไม่ตั้ง = พนักงานที่ไม่มีค่ารายคนจะไม่เข้าระบบเงินเดือน (ไม่ถูกแจ้งเตือน)
    payroll_default_salary: float = Field(default=0.0, ge=0)

    # วิธีเฉลี่ยเงินเมื่อเข้างานกลางรอบ
    #   calendar_30 = เงินเดือน ÷ 30 × จำนวนวันตามปฏิทินที่อยู่ในรอบ (แบบที่ HR ไทยใช้บ่อยสุด)
    #   work_days   = เงินเดือน ÷ วันทำงานทั้งรอบ × วันทำงานที่มีสิทธิ์
    payroll_prorate_basis: str = "calendar_30"
    payroll_calendar_divisor: int = Field(default=30, ge=1, le=31)

    # วันทำงานประจำสัปดาห์ตาม ISO (1=จันทร์ ... 7=อาทิตย์)
    payroll_work_weekdays: str = "1,2,3,4,5"
    # วันหยุดนักขัตฤกษ์/วันหยุดบริษัท คั่นด้วยจุลภาค เช่น "2026-10-13,2026-10-23"
    # วันหยุดเป็นวันที่ได้เงินอยู่แล้ว จึงถูกตัดออกจาก "วันที่ต้องมาทำงาน"
    # ไม่ใช่ถูกนับเป็นขาดงาน
    payroll_holidays: str = ""

    # หักเงินวันที่มาสาย (บาท/วัน) — 0 = ไม่หัก แค่รายงานให้เห็น
    payroll_late_deduction_per_day: float = Field(default=0.0, ge=0)

    # ประกันสังคม ม.33 — 5% ของค่าจ้าง ฐานคำนวณ 1,650-15,000 บาท (สูงสุด 750/เดือน)
    payroll_social_security_enabled: bool = True
    payroll_social_security_rate: float = Field(default=0.05, ge=0, le=1)
    payroll_social_security_floor: float = Field(default=1650.0, ge=0)
    payroll_social_security_ceiling: float = Field(default=15000.0, ge=0)

    # ⚠️ เงินเดือนเป็นข้อมูลส่วนตัว — ถ้า LINE_TARGET_ID เป็นกลุ่มที่มีคนอื่นอยู่
    # ให้ตั้งค่านี้เป็นห้องแชทส่วนตัว (userId ขึ้นต้นด้วย U) แยกจากกลุ่มแจ้งเข้างาน
    # เว้นว่าง = ใช้ LINE_TARGET_ID เดียวกับการแจ้งเตือนเช็คอิน
    payroll_line_target_id: str = ""

    # เวลาที่ควรส่งแจ้งเตือนแต่ละแบบ (เวลาไทย)
    # ตัดรอบส่งตอนเย็นเพราะต้องรอให้คนลงเวลาออกงานของวันที่ 26 ให้ครบก่อน
    payroll_cutoff_notice_time: str = "18:00"
    payroll_cycle_notice_time: str = "09:00"

    # เซิร์ฟเวอร์ดับข้ามวันแล้วเพิ่งกลับมา ยังส่งย้อนหลังได้ภายในกี่ชั่วโมง
    # เกินจากนี้ถือว่าตกรอบ ไม่ส่ง (กันสแปมย้อนหลังหลายรอบรวดเดียว)
    payroll_notice_catchup_hours: int = Field(default=36, ge=0, le=720)

    # --- กล้องวงจรปิด ONVIF (หมุนกล้อง + ภาพนิ่ง) ---
    # เซิร์ฟเวอร์ต้องอยู่วงเดียวกับกล้องถึงจะสั่งได้ (กล้องเป็น IP ในวง LAN)
    # ปิดทั้งระบบด้วย CAMERA_PTZ_ENABLED=false ถ้าเครื่องนั้นไม่มีกล้อง
    camera_ptz_enabled: bool = True
    camera_ptz_host: str = "192.168.1.101"
    camera_ptz_port: int = 80
    camera_ptz_username: str = ""       # กล้องที่ตั้งรหัสผ่านไว้ค่อยใส่
    camera_ptz_password: str = ""
    camera_ptz_speed: float = 0.6       # ความเร็วหมุน 0..1
    camera_ptz_zoom_speed: float = 0.6
    # กดปุ่ม 1 ครั้ง = หมุนนานเท่านี้แล้วหยุดเอง
    # ฝั่งเซิร์ฟเวอร์เป็นคนสั่งหยุด ไม่ได้รอให้มือถือส่ง stop มา —
    # ถ้าเน็ตมือถือหลุดกลางทาง กล้องจะได้ไม่หมุนค้างไม่มีที่สิ้นสุด
    camera_ptz_duration_ms: int = 600
    camera_ptz_max_duration_ms: int = 3000
    camera_ptz_invert_pan: bool = False   # ติดกล้องกลับด้านค่อยเปิด
    camera_ptz_invert_tilt: bool = False
    camera_timeout_seconds: float = 8.0

    # --- ความทนทานของภาพนิ่ง (ตัวที่ทำให้ภาพในแอปนิ่งหรือกระตุก) ---
    #
    # ดึงภาพจากกล้องช้ากว่าคุย SOAP มาก และกล้องตัวนี้รับคนดึงพร้อมกันหลายคน
    # ไม่ไหว (ตอบช้าลงเรื่อยๆ จนหลุด) จึงต้องคุมสามอย่าง:
    #
    #   1. cache — ภาพที่เพิ่งดึงมาใช้ซ้ำได้ในช่วงเวลาสั้นๆ หัวหน้าหลายคน
    #      เปิดพร้อมกันก็ยิงเข้ากล้องรอบเดียว
    #   2. timeout แยกจาก SOAP — ภาพช้ากว่า ต้องรอได้นานกว่านิดหน่อย แต่
    #      ต้องไม่นานจนเธรดของ FastAPI ถูกจองหมด
    #   3. stale — ภาพหลุดครั้งสองครั้งเป็นเรื่องปกติของกล้อง IP ส่งภาพ
    #      ล่าสุดที่ยังไม่เก่าเกินไปแทนที่จะตอบ error ให้แอปขึ้นเตือน
    # ตรวจว่ากล้องรับเสียงเข้าได้ไหม (RTSP DESCRIBE) — สั้นกว่าตัวอื่นเพราะเป็น
    # ข้อมูลเสริม ไม่ควรถ่วง /camera/status ที่แอปเรียกตอนเปิดแท็บ
    # บน LAN ปกติใช้เวลาไม่ถึงครึ่งวินาที ผลถูกจำไว้ 5 นาทีอยู่แล้ว
    camera_backchannel_timeout_seconds: float = 3.0

    camera_snapshot_cache_ms: int = 700
    camera_snapshot_timeout_seconds: float = 6.0
    camera_snapshot_stale_ms: int = 8000

    # ต่อกล้องใหม่ (discover profile ใหม่ทั้งชุด) ก็ต่อเมื่อพลาดติดกันเท่านี้
    # ครั้ง — พลาดครั้งเดียวแล้วรีเซ็ตทันทีทำให้เกิด "พายุ reconnect":
    # ทุกรอบต้องคุย SOAP ใหม่ 4 ครั้งก่อนได้ภาพ ยิ่งช้า ยิ่งพลาด วนไม่จบ
    camera_reconnect_after_failures: int = 3

    # ฟังเสียงจากไมค์ของกล้อง (ขาเข้าอย่างเดียว)
    # กล้องรุ่นที่ใช้อยู่ไม่มีลำโพงและไม่เปิด RTSP backchannel จึงพูดกลับไม่ได้
    camera_audio_enabled: bool = True
    camera_rtsp_url: str = "rtsp://192.168.1.101:554"
    camera_audio_bitrate: str = "32k"

    # เพดานอายุของสตรีมเสียงหนึ่งรอบ (วินาที)
    #
    # จำเป็นเพราะตัวเล่นเสียงฝั่งแอปไม่ยอมปิดสายเมื่อผู้ใช้กดหยุด (วัดได้ว่า
    # ค้างเกิน 77 วินาทีหลังกดหยุด) เซิร์ฟเวอร์จึงไม่มีทางรู้ว่าเลิกฟังแล้ว
    # ถ้าไม่มีเพดานนี้ ffmpeg จะจับ RTSP ของกล้องค้างไว้ข้ามคืน แล้วกล้องจะ
    # ช้าลงจนภาพนิ่งกับคำสั่งหมุนพลอยหลุดไปด้วย
    #
    # ครบเวลาแล้วสตรีมจะจบเอง แอปขึ้นว่า "สตรีมเสียงจบลง — กดฟังใหม่ได้"
    camera_audio_max_seconds: float = 600.0
    ffmpeg_path: str = ""   # เว้นว่าง = ให้ระบบหาเอง

    # --- พูดออกลำโพงกล้องผ่าน Tange TiRTC ---
    #
    # เสียงไม่วิ่งผ่าน Python: backend ออก token อายุสั้นให้บัญชีหัวหน้า แล้ว
    # Flutter TiRTC SDK ต่อ P2P/Cloud ไปยังกล้องโดยตรง SecretKeyId จึงต้องอยู่
    # ที่ server เท่านั้น ห้ามใส่ใน APK หรือส่งคืนจาก API
    camera_tirtc_enabled: bool = False
    camera_tirtc_app_id: str = ""
    camera_tirtc_access_key_id: str = ""
    camera_tirtc_secret_key_id: str = ""
    camera_tirtc_remote_id: str = ""
    camera_tirtc_token_ttl_seconds: int = Field(default=120, ge=30, le=300)
    camera_tirtc_stream_id: int = Field(default=14, ge=0, le=15)

    # --- ห้องช่วยเหลือระยะไกล (IT support: วิดีโอคอล + วาดชี้จุดบนภาพ) ---
    # ลิงก์เชิญมีอายุกี่นาที — หมดอายุแล้วผู้ใช้กดลิงก์เดิมเข้าไม่ได้อีก
    support_session_ttl_minutes: int = Field(default=120, ge=5, le=1440)
    # จำนวนห้องที่ยังเปิดค้างได้พร้อมกันต่อผู้ช่วย 1 คน (กันลืมปิดจนลิงก์เกลื่อน)
    support_max_open_sessions: int = Field(default=5, ge=1, le=50)
    # โดเมนหน้าเว็บสำหรับประกอบลิงก์เชิญ เช่น "https://checkin.example.com"
    # เว้นว่างได้ — หน้าเว็บจะประกอบลิงก์จากโดเมนที่เปิดอยู่เอง
    support_public_base_url: str = ""

    # เซิร์ฟเวอร์ STUN ใช้ให้เบราว์เซอร์สองฝั่งหาเส้นทางต่อตรงกันเจอ (คั่นด้วยจุลภาค)
    stun_servers: str = "stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302"
    # TURN ใช้เมื่อเน็ตฝั่งใดฝั่งหนึ่งต่อตรงไม่ได้ (เช่น 4G บางค่าย / เน็ตบริษัทที่ปิดพอร์ต)
    # เว้นว่าง = ใช้ STUN อย่างเดียว ซึ่งพอสำหรับเน็ตบ้าน/ออฟฟิศทั่วไป
    turn_url: str = ""
    turn_username: str = ""
    turn_password: str = ""

    # --- ยืนยันตัวตนรายวันตอนอยู่บ้าน (ดู DAILY_HOME_FACE_VERIFICATION_2026-09-11.md) ---
    # อายุของโจทย์: มีไว้กันการส่งหลักฐานเก่าเท่านั้น
    # **ไม่ใช่เส้นตายว่าต้องยืนยันก่อนกี่โมง** อยู่บ้านไม่มีสถานะสาย
    home_verification_challenge_ttl_seconds: int = Field(default=120, ge=30, le=900)
    # เพดานไฟล์หลักฐาน กันอัปโหลดไฟล์ใหญ่ผิดปกติ
    home_verification_max_photo_bytes: int = Field(default=8_000_000, ge=100_000)
    # ด้านสั้นที่สุดของภาพ กันภาพจิ๋วที่ตรวจสอบย้อนหลังไม่ได้
    home_verification_min_photo_pixels: int = Field(default=160, ge=64, le=4096)

    # โดเมนที่อนุญาตให้เรียก API จากเบราว์เซอร์ (คั่นด้วยจุลภาค)
    # production: ตั้งเป็นโดเมนจริง เช่น "https://checkin.example.com"
    allowed_origins: str = "*"

    @property
    def origins_list(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def ice_servers_list(self) -> list[dict]:
        """รายการ ICE server ที่ส่งให้เบราว์เซอร์ใช้ตอนต่อสายวิดีโอ"""
        servers: list[dict] = []
        urls = [u.strip() for u in self.stun_servers.split(",") if u.strip()]
        if urls:
            servers.append({"urls": urls})
        turn = self.turn_url.strip()
        if turn:
            entry: dict = {"urls": [u.strip() for u in turn.split(",") if u.strip()]}
            if self.turn_username:
                entry["username"] = self.turn_username
                entry["credential"] = self.turn_password
            servers.append(entry)
        return servers

    @property
    def camera_tirtc_missing_fields(self) -> list[str]:
        """ชื่อ env ที่ยังไม่มีค่า โดยไม่แตะหรือเปิดเผยค่าความลับ"""
        fields = {
            "CAMERA_TIRTC_APP_ID": self.camera_tirtc_app_id,
            "CAMERA_TIRTC_ACCESS_KEY_ID": self.camera_tirtc_access_key_id,
            "CAMERA_TIRTC_SECRET_KEY_ID": self.camera_tirtc_secret_key_id,
            "CAMERA_TIRTC_REMOTE_ID": self.camera_tirtc_remote_id,
        }
        return [name for name, value in fields.items() if not value.strip()]

    @property
    def camera_tirtc_ready(self) -> bool:
        return self.camera_tirtc_enabled and not self.camera_tirtc_missing_fields

    @property
    def offices_list(self) -> list[dict]:
        """รายการสถานที่ที่เช็คอินได้ — คืนอย่างน้อย 1 รายการเสมอ

        อ่านจาก OFFICES (JSON) ถ้าตั้งไว้ ไม่งั้นใช้ office_* เป็นสถานที่เดียว
        ค่าที่ผิดรูปแบบจะถูกข้าม เพื่อไม่ให้ระบบล่มเพราะพิมพ์ JSON ผิด
        """
        raw = (self.offices or "").strip()
        if raw:
            try:
                items = json.loads(raw)
            except json.JSONDecodeError:
                items = []
            result = []
            for it in items if isinstance(items, list) else []:
                try:
                    result.append(
                        {
                            "name": str(it["name"]),
                            "lat": float(it["lat"]),
                            "lng": float(it["lng"]),
                            "radius_km": float(it.get("radius_km", self.geofence_radius_km)),
                            "allow_checkout": bool(it.get("allow_checkout", True)),
                            "category": str(
                                it.get("category")
                                or it.get("type")
                                or it.get("location_type")
                                or ""
                            ),
                        }
                    )
                except (KeyError, TypeError, ValueError):
                    continue
            if result:
                return result

        return [
            {
                "name": self.office_name,
                "lat": self.office_lat,
                "lng": self.office_lng,
                "radius_km": self.geofence_radius_km,
                "allow_checkout": True,
                "category": "work",
            }
        ]

    @property
    def payroll_weekdays_set(self) -> set[int]:
        """วันทำงานประจำสัปดาห์ — ค่าผิดรูปแบบถอยไปใช้จันทร์-ศุกร์

        ตั้งใจไม่ให้ระบบล่มเพราะพิมพ์ผิด เหมือน offices_list และ work_start
        """
        result = set()
        for part in (self.payroll_work_weekdays or "").split(","):
            part = part.strip()
            if not part:
                continue
            try:
                value = int(part)
            except ValueError:
                continue
            if 1 <= value <= 7:
                result.add(value)
        return result or {1, 2, 3, 4, 5}

    @property
    def payroll_holidays_set(self) -> set[date]:
        """วันหยุดที่ตั้งไว้ใน .env — บรรทัดที่พิมพ์ผิดถูกข้าม ไม่ทำให้ระบบล่ม"""
        result: set[date] = set()
        for part in (self.payroll_holidays or "").split(","):
            part = part.strip()
            if not part:
                continue
            try:
                result.add(date.fromisoformat(part))
            except ValueError:
                continue
        return result

    @property
    def payroll_target_id(self) -> str:
        """ห้องที่จะส่งสรุปเงินเดือนไป — ไม่ได้ตั้งแยกก็ใช้ห้องเดียวกับเช็คอิน"""
        return (self.payroll_line_target_id or self.line_target_id).strip()

    @property
    def payroll_cutoff_notice_at(self) -> time:
        return _parse_hhmm(self.payroll_cutoff_notice_time, time(18, 0))

    @property
    def payroll_cycle_notice_at(self) -> time:
        return _parse_hhmm(self.payroll_cycle_notice_time, time(9, 0))

    @property
    def work_start(self) -> time:
        """เวลาเข้างานมาตรฐาน (เวลาไทย)"""
        return _parse_hhmm(self.work_start_time, DEFAULT_WORK_START)

    @property
    def work_end(self) -> time:
        """เวลาออกงานมาตรฐาน (เวลาไทย)"""
        return _parse_hhmm(self.work_end_time, DEFAULT_WORK_END)

    @property
    def work_schedule_dict(self) -> dict:
        """เกณฑ์เวลาทำงานในรูปแบบที่ส่งให้แอป/เว็บได้ตรงๆ

        แอปใช้ค่าชุดนี้คำนวณป้าย "สาย/ตรงเวลา" เองบนหน้าจอ ให้ได้ผลตรงกับ
        ข้อความที่ backend ส่งเข้า LINE โดยไม่ต้องฝังเวลาไว้ใน APK
        """
        start, end = self.work_start, self.work_end
        return {
            "work_start": start.strftime("%H:%M"),
            "work_end": end.strftime("%H:%M"),
            "late_grace_minutes": self.late_grace_minutes,
            "early_leave_grace_minutes": self.early_leave_grace_minutes,
            "enabled": self.attendance_rules_enabled,
        }


settings = Settings()
