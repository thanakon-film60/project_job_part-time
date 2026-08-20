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
    #   OFFICES=[{"name":"THANAKON-BOX","lat":13.9231953,"lng":100.5195808,"radius_km":2.0},
    #            {"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0},
    #            {"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2}]
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
            }
        ]


settings = Settings()
