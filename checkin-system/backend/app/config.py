from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql://checkin:checkin@localhost:5432/checkin"

    office_lat: float = 13.9231953
    office_lng: float = 100.5195808
    office_name: str = "MARDODI"
    geofence_radius_km: float = 2.0

    secret_key: str = "change-this-to-a-long-random-string"
    access_token_expire_minutes: int = 720
    algorithm: str = "HS256"

    storage_dir: str = "storage"

    # โดเมนที่อนุญาตให้เรียก API จากเบราว์เซอร์ (คั่นด้วยจุลภาค)
    # production: ตั้งเป็นโดเมนจริง เช่น "https://checkin.example.com"
    allowed_origins: str = "*"

    @property
    def origins_list(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]


settings = Settings()
