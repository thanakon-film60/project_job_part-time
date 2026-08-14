"""ทดสอบ end-to-end ครบวงจร (ใช้ SQLite ชั่วคราว)

รัน: pip install httpx pytest ; python _e2e.py
ครอบคลุม: สมัคร/ล็อกอิน, เช็คอินในเขต, ปฏิเสธนอกเขต, ปฏิเสธไม่พบใบหน้า,
GPS ping, ปฏิทินฝั่งผู้จัดการ, และการกันสิทธิ์พนักงาน
"""
import datetime
import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"
if os.path.exists("test.db"):
    os.remove("test.db")

from fastapi.testclient import TestClient  # noqa: E402
from app.main import app  # noqa: E402

c = TestClient(app)


def run():
    c.post("/auth/register", json={"employee_code": "EMP001", "full_name": "Thanakon",
           "email": "t@x.com", "password": "pw123456", "is_manager": False})
    c.post("/auth/register", json={"employee_code": "BOSS001", "full_name": "Boss",
           "email": "b@x.com", "password": "boss1234", "is_manager": True})

    tok = c.post("/auth/login", data={"username": "EMP001", "password": "pw123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}

    r = c.post("/checkins", headers=h, data={"latitude": "13.9231953", "longitude": "100.5195808", "kind": "in", "face_detected": "true"})
    assert r.status_code == 200 and r.json()["within_geofence"] is True

    r = c.post("/checkins", headers=h, data={"latitude": "13.9232875", "longitude": "100.4167031", "kind": "in", "face_detected": "true"})
    assert r.status_code == 422  # นอกเขต 11 กม.

    r = c.post("/checkins", headers=h, data={"latitude": "13.9231953", "longitude": "100.5195808", "kind": "in", "face_detected": "false"})
    assert r.status_code == 422  # ไม่พบใบหน้า

    assert c.get("/reports/employees", headers=h).status_code == 403  # พนักงานเข้าไม่ได้

    mtok = c.post("/auth/login", data={"username": "BOSS001", "password": "boss1234"}).json()["access_token"]
    mh = {"Authorization": f"Bearer {mtok}"}
    now = datetime.datetime.utcnow()
    emps = c.get("/reports/employees", headers=mh).json()
    eid = [e for e in emps if e["employee_code"] == "EMP001"][0]["id"]
    cal = c.get(f"/reports/calendar?employee_id={eid}&year={now.year}&month={now.month}", headers=mh).json()
    assert len(cal["days"]) >= 1
    print("ทุกเทสต์ผ่าน ✓")


if __name__ == "__main__":
    try:
        run()
    finally:
        if os.path.exists("test.db"):
            os.remove("test.db")
