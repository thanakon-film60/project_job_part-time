import json

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://checkin:checkin@localhost:5432/checkin"

    # --- ออฟฟิศหลัก (ของเดิม ใช้เป็นค่า fallback ถ้าไม่ได้ตั้ง OFFICES) ---
    office_lat: float = 13.9231953
    office_lng: float = 100.5195808
    office_name: str = "THANAKON-BOX"
    geofence_radius_km: float = 2.0

    # --- รองรับหลายสถานที่ ---
    # ตั้งใน .env เป็น JSON บรรทัดเดียว เช่น
    #   OFFICES=[{"name":"THANAKON-BOX","lat":13.9231953,"lng":100.5195808,"radius_km":2.0,"category":"work"},
    #            {"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0,"category":"hospital"},
    #            {"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2,"category":"home"}]
    # ถ้าเว้นว่างไว้ ระบบจะใช้ office_* ด้านบนเป็นสถานที่เดียว (เข้ากันได้กับของเดิม)
    offices: str = ""

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
    ffmpeg_path: str = ""   # เว้นว่าง = ให้ระบบหาเอง

    # โดเมนที่อนุญาตให้เรียก API จากเบราว์เซอร์ (คั่นด้วยจุลภาค)
    # production: ตั้งเป็นโดเมนจริง เช่น "https://checkin.example.com"
    allowed_origins: str = "*"

    @property
    def origins_list(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

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


settings = Settings()
