"""ทดสอบ end-to-end ครบวงจร (ใช้ SQLite ชั่วคราว)

รัน: pip install httpx2 pytest ; python tests_e2e.py
ครอบคลุม: สมัคร/ล็อกอิน, เช็คอินในเขต, ปฏิเสธนอกเขต, ปฏิเสธไม่พบใบหน้า,
GPS ping, ปฏิทินฝั่งผู้จัดการ, และการกันสิทธิ์พนักงาน
"""
import datetime
import base64
import hashlib
import hmac
import json
import logging
import os
import shutil
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

os.environ["DATABASE_URL"] = "sqlite:///./test.db"
# เก็บรูปที่เทสต์อัปโหลดไว้คนละที่กับของจริง ไม่งั้นไฟล์ปลอมจะไปปนใน storage/
# ของเซิร์ฟเวอร์แล้วลบออกยาก (settings.storage_dir ถูกอ่านตอน import จึงต้องตั้งก่อน)
os.environ["STORAGE_DIR"] = "./test_storage"
os.environ["OFFICES"] = '[{"name":"THANAKON-BOX","lat":13.9231953,"lng":100.5195808,"radius_km":2.0,"category":"work"},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0,"category":"hospital"},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2,"category":"home"}]'
os.environ["CAMERA_TIRTC_ENABLED"] = "true"
os.environ["CAMERA_TIRTC_APP_ID"] = "test-app"
os.environ["CAMERA_TIRTC_ACCESS_KEY_ID"] = "test-access"
os.environ["CAMERA_TIRTC_SECRET_KEY_ID"] = "test-secret"
os.environ["CAMERA_TIRTC_REMOTE_ID"] = "test-camera"
if os.path.exists("test.db"):
    os.remove("test.db")
shutil.rmtree("test_storage", ignore_errors=True)

from fastapi.testclient import TestClient  # noqa: E402
from app.main import app  # noqa: E402
from app.database import engine  # noqa: E402
from app.routers import checkins as checkins_router  # noqa: E402

c = TestClient(app)


def run():
    line_messages: list[str] = []

    def fake_push_text(text: str, to: str | None = None) -> bool:
        line_messages.append(text)
        return True

    checkins_router.push_text = fake_push_text

    c.post("/auth/register", json={"employee_code": "EMP001", "full_name": "Thanakon",
           "email": "t@x.com", "password": "pw123456", "is_manager": False})
    c.post("/auth/register", json={"employee_code": "BOSS001", "full_name": "Boss",
           "email": "b@x.com", "password": "boss1234", "is_manager": True})

    tok = c.post("/auth/login", data={"username": "EMP001", "password": "pw123456"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}

    r = c.post("/checkins", headers=h, data={"latitude": "13.9231953", "longitude": "100.5195808", "kind": "in", "face_detected": "true"})
    assert r.status_code == 200 and r.json()["within_geofence"] is True
    msg = line_messages[-1]
    assert msg.startswith("Thanakon ได้ทำการเข้างานแล้ว (")
    assert "ประเภทสถานที่: ที่ทำงาน" in msg
    assert "สถานที่ใกล้สุด: THANAKON-BOX" in msg
    assert "ระยะห่างจากที่ทำงาน" in msg

    # อยู่บ้าน = ไม่ได้ไปทำงาน จึงกดออกงานที่บ้านไม่ได้
    # (evaluate_location(work_only=True) ตัดสถานที่หมวด home ทิ้งตอน kind="out")
    r = c.post("/checkins", headers=h, data={"latitude": "13.8865664", "longitude": "100.5066278", "kind": "out", "face_detected": "true"})
    assert r.status_code == 422, r.text

    # ลงเวลาที่บ้านได้ แต่เป็นแค่ "ถึงบ้านแล้ว" ไม่ใช่การเข้างาน และไม่ต้องมีออกงานตามมา
    r = c.post("/checkins", headers=h, data={"latitude": "13.8865664", "longitude": "100.5066278", "kind": "in", "face_detected": "true"})
    assert r.status_code == 200 and r.json()["office_name"] == "ถึงบ้านแล้ว"
    msg = line_messages[-1]
    assert msg.startswith("Thanakon อยู่บ้านแล้ว (")
    assert "ไม่นับเป็นการเข้างานและไม่มีออกงาน" in msg
    assert "สถานที่ใกล้สุด: ถึงบ้านแล้ว" in msg

    r = c.post("/checkins", headers=h, data={"latitude": "13.8918358", "longitude": "100.563443", "kind": "in", "face_detected": "true"})
    assert r.status_code == 200 and r.json()["office_name"] == "BJH Bangkok"
    msg = line_messages[-1]
    assert msg.startswith("Thanakon ได้ทำการเข้างานแล้ว (")
    assert "ประเภทสถานที่: โรงพยาบาล" in msg
    assert "สถานที่ใกล้สุด: BJH Bangkok" in msg

    r = c.post("/checkins", headers=h, data={"latitude": "13.9232875", "longitude": "100.4167031", "kind": "in", "face_detected": "true"})
    assert r.status_code == 422  # นอกเขต 11 กม.

    r = c.post("/checkins", headers=h, data={"latitude": "13.9231953", "longitude": "100.5195808", "kind": "in", "face_detected": "false"})
    assert r.status_code == 422  # ไม่พบใบหน้า

    assert c.get("/reports/employees", headers=h).status_code == 403  # พนักงานเข้าไม่ได้
    assert c.post("/camera/talkback/token", headers=h).status_code == 403

    mtok = c.post("/auth/login", data={"username": "BOSS001", "password": "boss1234"}).json()["access_token"]
    mh = {"Authorization": f"Bearer {mtok}"}
    _test_tirtc_token(mh)
    now = datetime.datetime.now(datetime.UTC)
    emps = c.get("/reports/employees", headers=mh).json()
    eid = [e for e in emps if e["employee_code"] == "EMP001"][0]["id"]
    cal = c.get(f"/reports/calendar?employee_id={eid}&year={now.year}&month={now.month}", headers=mh).json()
    assert len(cal["days"]) >= 1

    _test_face_gallery(h, mh, eid)
    print("ทุกเทสต์ผ่าน ✓")


def _decode_base64url(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _test_tirtc_token(manager_headers: dict) -> None:
    """เฉพาะหัวหน้าออก token ได้ และ API ไม่ทำ SecretKeyId หลุดออกมา"""
    # แม้ client พยายามส่งเป้าหมายอื่นมา endpoint ต้องไม่รับและยังใช้ค่าจาก env
    first = c.post(
        "/camera/talkback/token",
        headers=manager_headers,
        json={"remote_id": "attacker-selected-camera"},
    )
    second = c.post("/camera/talkback/token", headers=manager_headers)
    assert first.status_code == 200, first.text
    assert first.headers["cache-control"] == "no-store"
    assert first.headers["pragma"] == "no-cache"

    data = first.json()
    assert data["provider"] == "tirtc"
    assert data["app_id"] == "test-app"
    assert data["remote_id"] == "test-camera"
    assert data["stream_id"] == 14
    assert data["expires_at"] - data["issued_at"] == 120
    assert data["token"] != second.json()["token"], "token แต่ละครั้งต้องมี nonce ใหม่"
    assert "test-secret" not in first.text

    version, payload_b64, signature_b64 = data["token"].split(".")
    assert version == "v1"
    payload = json.loads(_decode_base64url(payload_b64))
    assert payload["sub"] == "employee:BOSS001"
    assert payload["scope"] == "connect:device://test-camera"
    assert payload["iss"] == "test-access"
    assert payload["exp"] == data["expires_at"]

    expected = hmac.new(
        b"test-secret",
        payload_b64.encode("ascii"),
        hashlib.sha256,
    ).digest()
    assert hmac.compare_digest(_decode_base64url(signature_b64), expected)

    spec = c.get("/openapi.json").json()
    assert "post" in spec["paths"]["/camera/talkback/token"]
    status_fields = spec["components"]["schemas"]["CameraStatusOut"]["properties"]
    assert {"talkback_ready", "talkback_transport", "talkback_token_path"} <= set(
        status_fields
    )


def _test_face_gallery(h: dict, mh: dict, employee_id: int) -> None:
    """รูปใบหน้าอ้างอิง: จัดลำดับเอง + ลบทิ้ง (พนักงานทำเองได้)

    ลำดับสำคัญเพราะ "รูปแรก" ถูกใช้เป็นรูปประจำตัวทุกที่ที่ระบบแสดงรูปพนักงาน
    """
    ids = []
    for i in range(3):
        r = c.post(
            "/faces/enroll",
            headers=h,
            files={"photo": (f"face{i}.jpg", b"fake-jpeg-bytes", "image/jpeg")},
            data={"source": "mobile", "note": f"rup-{i}"},
        )
        assert r.status_code == 200, r.text
        ids.append(r.json()["id"])

    # ยังไม่เคยจัดลำดับ = เรียงตามเวลาบันทึก ใหม่สุดขึ้นก่อน (พฤติกรรมเดิม)
    assert [f["id"] for f in c.get("/faces/me", headers=h).json()] == list(reversed(ids))

    # ลากใบเก่าสุดขึ้นมาเป็นรูปประจำตัว
    wanted = [ids[0], ids[2], ids[1]]
    r = c.put("/faces/order", headers=h, json={"face_ids": wanted})
    assert r.status_code == 200, r.text
    assert [f["id"] for f in r.json()] == wanted
    assert [f["sort_order"] for f in r.json()] == [0, 1, 2]
    assert [f["id"] for f in c.get("/faces/me", headers=h).json()] == wanted

    # หน้าแฟ้มพนักงานของหัวหน้าต้องเห็นลำดับเดียวกัน (รูปประจำตัวตรงกัน)
    history = c.get(
        f"/reports/employees/{employee_id}/history?year={datetime.datetime.now(datetime.UTC).year}"
        f"&month={datetime.datetime.now(datetime.UTC).month}",
        headers=mh,
    ).json()
    assert [f["id"] for f in history["face_profiles"]] == wanted

    # ส่งมาไม่ครบทุกใบ = ปฏิเสธ ไม่งั้นลำดับจะค้างครึ่ง ๆ กลาง ๆ
    assert c.put("/faces/order", headers=h, json={"face_ids": [ids[0]]}).status_code == 400

    # ลบรูปของตัวเอง: แถวหาย ไฟล์หาย และลำดับไล่ใหม่ต่อเนื่องไม่มีช่องว่าง
    photo_path = _face_photo_path(ids[2])
    assert os.path.exists(photo_path)
    assert c.delete(f"/faces/{ids[2]}", headers=h).status_code == 204
    assert not os.path.exists(photo_path), "ลบแถวแล้วแต่ไฟล์รูปยังค้างบนดิสก์"

    left = c.get("/faces/me", headers=h).json()
    assert [f["id"] for f in left] == [ids[0], ids[1]]
    assert [f["sort_order"] for f in left] == [0, 1]

    assert c.delete(f"/faces/{ids[2]}", headers=h).status_code == 404

    # คนอื่นแตะรูปเราไม่ได้ (แม้จะดึงรายการมาถูก id ก็ตาม)
    c.post("/auth/register", json={"employee_code": "EMP002", "full_name": "Someone",
           "email": "s@x.com", "password": "pw123456", "is_manager": False})
    otok = c.post("/auth/login", data={"username": "EMP002", "password": "pw123456"}).json()["access_token"]
    oh = {"Authorization": f"Bearer {otok}"}
    assert c.delete(f"/faces/{ids[0]}", headers=oh).status_code == 403
    assert c.put("/faces/order", headers=oh, json={"face_ids": [ids[0], ids[1]]}).status_code == 404


def _face_photo_path(face_id: int) -> str:
    from app.database import SessionLocal
    from app.models import FaceProfile

    with SessionLocal() as db:
        return db.query(FaceProfile).filter(FaceProfile.id == face_id).first().photo_path


if __name__ == "__main__":
    try:
        run()
    finally:
        c.close()
        engine.dispose()
        if os.path.exists("test.db"):
            os.remove("test.db")
        # routers/line.py เปิด FileHandler ค้างไว้ใต้ storage_dir ตั้งแต่ import
        # ถ้าไม่ปิดก่อน Windows จะลบโฟลเดอร์ไม่ได้เพราะไฟล์ยังถูกถือครองอยู่
        logging.shutdown()
        shutil.rmtree("test_storage", ignore_errors=True)
