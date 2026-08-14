"""สร้างข้อมูลตัวอย่าง: พนักงาน 1 คน + ผู้จัดการ 1 คน + เช็คอินตัวอย่าง

รัน: python seed.py
"""
from datetime import datetime, timedelta

from app.database import Base, SessionLocal, engine
from app.geofence import evaluate_location
from app.models import CheckIn, Employee
from app.security import hash_password

Base.metadata.create_all(bind=engine)
db = SessionLocal()


def get_or_create(code, name, email, pw, manager):
    e = db.query(Employee).filter(Employee.employee_code == code).first()
    if e:
        return e
    e = Employee(
        employee_code=code,
        full_name=name,
        email=email,
        hashed_password=hash_password(pw),
        is_manager=manager,
    )
    db.add(e)
    db.commit()
    db.refresh(e)
    return e


emp = get_or_create("EMP001", "Thanakon", "thanakon.film60@gmail.com", "password123", False)
boss = get_or_create("BOSS001", "หัวหน้า", "boss@mardodi.co.th", "boss12345", True)

# เช็คอินตัวอย่างในเขตออฟฟิศ 5 วันย้อนหลัง
office = (13.9231953, 100.5195808)
if db.query(CheckIn).filter(CheckIn.employee_id == emp.id).count() == 0:
    for d in range(5):
        day = datetime.utcnow() - timedelta(days=d)
        for kind, hour in (("in", 8), ("out", 17)):
            ts = day.replace(hour=hour, minute=5 * d, second=0, microsecond=0)
            dist, within = evaluate_location(*office)
            db.add(
                CheckIn(
                    employee_id=emp.id,
                    kind=kind,
                    timestamp=ts,
                    latitude=office[0],
                    longitude=office[1],
                    distance_km=dist,
                    within_geofence=within,
                    face_detected=True,
                )
            )
    db.commit()

print("Seed เสร็จ:")
print("  พนักงาน: EMP001 / password123")
print("  ผู้จัดการ: BOSS001 / boss12345")
db.close()
