from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import Base, apply_pending_migrations, engine
from .routers import (
    addresses,
    app_release,
    auth,
    checkins,
    employee_management,
    employment_options,
    faces,
    line,
    locations,
    reports,
)

# สร้างตารางอัตโนมัติเมื่อสตาร์ต (สำหรับ dev; production ควรใช้ Alembic)
Base.metadata.create_all(bind=engine)
# เติมคอลัมน์ที่เพิ่มทีหลังให้ฐานข้อมูลเดิม (create_all ไม่ทำให้)
apply_pending_migrations()

app = FastAPI(title="ระบบเช็คอินเข้างาน THANAKON-ROOM", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins_list,  # ตั้งผ่าน ALLOWED_ORIGINS ใน production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(app_release.router)
app.include_router(app_release.boss_router)
app.include_router(addresses.router)
app.include_router(employment_options.router)
app.include_router(employee_management.router)
app.include_router(auth.router)
app.include_router(checkins.router)
app.include_router(faces.router)
app.include_router(line.router)
app.include_router(locations.router)
app.include_router(reports.router)


@app.get("/")
def root():
    return {
        "service": "checkin-thanakon-box",
        "offices": settings.offices_list,
        # ของเดิม เก็บไว้ให้ client เก่ายังอ่านได้
        "office": settings.office_name,
        "geofence_radius_km": settings.geofence_radius_km,
    }


@app.get("/health")
def health():
    return {"status": "ok"}
