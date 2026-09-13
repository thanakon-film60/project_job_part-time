"""python -m unittest test_home_verifications -v

SQLite แยกต่างหาก ไม่แตะฐานข้อมูล production และไม่ส่ง LINE จริง
ครอบเกณฑ์ตรวจรับในหัวข้อ 7 และ 14 ของ DAILY_HOME_FACE_VERIFICATION_2026-09-11.md
"""
import struct
import unittest
import uuid
import zlib
from datetime import datetime, timedelta
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import get_db
from app.home_verification_models import HomeVerification, HomeVerificationChallenge
from app.models import Employee, FaceProfile
from app.routers.home_verifications import router
from app.security import create_access_token

# พิกัดบ้าน/ที่ทำงานที่ใช้ตลอดไฟล์นี้ — ตั้งเป็น OFFICES ของ settings ตอน setUp
HOME = {"name": "ถึงบ้านแล้ว", "lat": 13.8865664, "lng": 100.5066278,
        "radius_km": 0.2, "allow_checkout": False, "category": "home"}
WORK = {"name": "Motta & Montipa (Head office)", "lat": 13.9040518, "lng": 100.5391995,
        "radius_km": 0.5, "allow_checkout": True, "category": "work"}


def png_bytes(width: int = 320, height: int = 320, seed: int = 0) -> bytes:
    """สร้าง PNG จริงที่ไบต์ไม่ซ้ำกันตาม seed (ใช้ทดสอบการกันรูปซ้ำ)"""
    raw = b"".join(
        b"\x00" + bytes(((x + y + seed) % 256) for x in range(width)) for y in range(height)
    )

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


class HomeVerificationTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        for table in (Employee.__table__, FaceProfile.__table__,
                      HomeVerificationChallenge.__table__, HomeVerification.__table__):
            table.create(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        with self.sessions() as db:
            # 1 = พนักงานมีใบหน้าแล้ว, 2 = พนักงานยังไม่ลงทะเบียนใบหน้า, 10 = หัวหน้า (มีใบหน้า)
            for emp_id, manager in [(1, False), (2, False), (10, True)]:
                db.add(Employee(id=emp_id, employee_code=f"T{emp_id}", full_name=f"Test {emp_id}",
                                email=f"t{emp_id}@example.invalid",
                                hashed_password="not-a-real-password", is_manager=manager))
            db.add(FaceProfile(employee_id=1, photo_path="ref-1.jpg"))
            db.add(FaceProfile(employee_id=10, photo_path="ref-10.jpg"))
            db.commit()

        app = FastAPI()
        app.include_router(router)

        def test_db():
            with self.sessions() as db:
                yield db

        app.dependency_overrides[get_db] = test_db
        self.client = TestClient(app)

        # ไม่ยิง LINE จริง และล็อกสถานที่ให้แน่นอนไม่ขึ้นกับ .env ของเครื่องที่รันเทส
        self._patches = [
            patch("app.routers.home_verifications.push_text"),
            patch("app.config.settings.offices", ""),
            patch("app.config.Settings.offices_list",
                  property(lambda self: [WORK, HOME])),
        ]
        for p in self._patches:
            p.start()
        # เก็บชื่อไว้เอง — อ่านจาก settings ตอน tearDown ไม่ได้ เพราะ patch ถูกถอนไปแล้ว
        self.storage_dir = f"storage-test-{uuid.uuid4().hex}"
        self.storage = patch("app.config.settings.storage_dir", self.storage_dir)
        self.storage.start()

    def tearDown(self):
        import shutil
        self.storage.stop()
        for p in reversed(self._patches):
            p.stop()
        self.client.close()
        self.engine.dispose()
        shutil.rmtree(self.storage_dir, ignore_errors=True)

    # ---------- helpers ----------

    def headers(self, emp_id: int) -> dict:
        return {"Authorization": f"Bearer {create_access_token(f'T{emp_id}')}"}

    def challenge(self, emp_id: int = 1) -> str:
        res = self.client.post("/home-verifications/challenges", headers=self.headers(emp_id))
        self.assertEqual(res.status_code, 200, res.text)
        return res.json()["challenge_id"]

    def submit(self, emp_id=1, challenge_id=None, request_id=None, lat=None, lng=None,
               photo=None, accuracy=None):
        data = {
            "request_id": request_id or str(uuid.uuid4()),
            "challenge_id": challenge_id if challenge_id is not None else self.challenge(emp_id),
            "latitude": str(HOME["lat"] if lat is None else lat),
            "longitude": str(HOME["lng"] if lng is None else lng),
        }
        if accuracy is not None:
            data["location_accuracy_m"] = str(accuracy)
        files = {"photo": ("scan.png", photo or png_bytes(seed=uuid.uuid4().int % 200), "image/png")}
        return self.client.post("/home-verifications", data=data, files=files,
                                headers=self.headers(emp_id))

    def code(self, res) -> str:
        return res.json()["detail"]["code"]

    # ---------- เส้นทางหลัก ----------

    def test_verify_at_home_succeeds_and_carries_no_work_time_fields(self):
        res = self.submit(accuracy=12.5)
        self.assertEqual(res.status_code, 200, res.text)
        body = res.json()
        self.assertEqual(body["status"], "verified")
        self.assertEqual(body["category"], "home")
        self.assertEqual(body["office_name"], HOME["name"])
        self.assertEqual(body["timezone"], "Asia/Bangkok")
        self.assertEqual(body["location_accuracy_m"], 12.5)
        # อยู่บ้านต้องไม่มีสนามใด ๆ ที่สื่อถึงเวลางาน
        for banned in ("late_minutes", "expected_check_in", "expected_check_out",
                       "work_hours", "kind", "check_in", "check_out"):
            self.assertNotIn(banned, body)

    def test_manager_is_not_exempt_from_scanning(self):
        """ต่างจาก POST /checkins ที่ยกเว้นหัวหน้า — flow บ้านต้องสแกนทุกบทบาท"""
        res = self.submit(emp_id=10)
        self.assertEqual(res.status_code, 200, res.text)
        self.assertEqual(res.json()["category"], "home")

        # และหัวหน้าก็ถูกปฏิเสธเหมือนกันเมื่อหลักฐานใช้ไม่ได้
        bad = self.submit(emp_id=10, photo=b"not-an-image-at-all")
        self.assertEqual(bad.status_code, 422)
        self.assertEqual(self.code(bad), "evidence_invalid")

    def test_login_alone_does_not_count_as_verified_today(self):
        res = self.client.get("/home-verifications/me", headers=self.headers(1))
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertFalse(body["verified"])
        self.assertEqual(body["verifications"], [])
        self.assertEqual(body["server_date"], body["date"])

    def test_enrolled_face_alone_does_not_verify_the_day(self):
        """พนักงาน 1 มี FaceProfile อยู่แล้ว แต่ยังต้องขึ้นว่ายังไม่ยืนยัน"""
        res = self.client.get("/home-verifications/me", headers=self.headers(1))
        self.assertFalse(res.json()["verified"])

    def test_verification_appears_for_user_and_manager(self):
        self.submit()
        mine = self.client.get("/home-verifications/me", headers=self.headers(1)).json()
        self.assertTrue(mine["verified"])
        self.assertEqual(len(mine["verifications"]), 1)

        boss_view = self.client.get("/home-verifications/employee/1", headers=self.headers(10))
        self.assertEqual(boss_view.status_code, 200)
        self.assertEqual(boss_view.json()["verifications"][0]["id"],
                         mine["verifications"][0]["id"])

    def test_employee_cannot_read_other_peoples_verifications(self):
        self.submit()
        res = self.client.get("/home-verifications/employee/1", headers=self.headers(2))
        self.assertEqual(res.status_code, 403)

    # ---------- การยืนยันซ้ำในวันเดียวกัน ----------

    def test_second_verification_same_day_needs_a_new_challenge_and_scan(self):
        first = self.submit()
        self.assertEqual(first.status_code, 200)
        second = self.submit()
        self.assertEqual(second.status_code, 200, second.text)
        self.assertNotEqual(first.json()["id"], second.json()["id"])

        day = self.client.get("/home-verifications/me", headers=self.headers(1)).json()
        self.assertEqual(len(day["verifications"]), 2)

    def test_challenge_cannot_be_used_twice(self):
        challenge_id = self.challenge()
        first = self.submit(challenge_id=challenge_id)
        self.assertEqual(first.status_code, 200)
        again = self.submit(challenge_id=challenge_id)
        self.assertEqual(again.status_code, 409)
        self.assertEqual(self.code(again), "challenge_used")

    def test_reusing_an_old_photo_is_rejected(self):
        photo = png_bytes(seed=7)
        self.assertEqual(self.submit(photo=photo).status_code, 200)
        again = self.submit(photo=photo)
        self.assertEqual(again.status_code, 422)
        self.assertEqual(self.code(again), "evidence_reused")

    def test_challenge_of_another_account_is_rejected(self):
        stolen = self.challenge(emp_id=1)
        res = self.submit(emp_id=10, challenge_id=stolen)
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "challenge_invalid")

    def test_expired_challenge_is_rejected(self):
        challenge_id = self.challenge()
        with self.sessions() as db:
            row = db.query(HomeVerificationChallenge).filter_by(challenge_id=challenge_id).one()
            row.expires_at = datetime.utcnow() - timedelta(seconds=1)
            db.commit()
        res = self.submit(challenge_id=challenge_id)
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "challenge_expired")

    # ---------- ตำแหน่งและใบหน้าอ้างอิง ----------

    def test_outside_home_cannot_verify(self):
        res = self.submit(lat=WORK["lat"], lng=WORK["lng"])
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "outside_home")

    def test_far_from_everything_cannot_verify(self):
        res = self.submit(lat=18.7883, lng=98.9853)  # เชียงใหม่
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "outside_home")

    def test_missing_reference_face_blocks_verification(self):
        res = self.submit(emp_id=2)
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "face_not_enrolled")

    def test_challenge_carries_machine_readable_action_code(self):
        """แอปต้องเลือกวิธีตรวจท่าจากรหัส ไม่ใช่เดาจากข้อความไทย"""
        res = self.client.post("/home-verifications/challenges", headers=self.headers(1))
        body = res.json()
        self.assertIn(body["action_code"],
                      {"look_straight", "turn_left", "turn_right", "blink"})
        # รหัสกับข้อความต้องเป็นคู่กันเสมอ
        from app.home_verification import CHALLENGE_ACTIONS
        self.assertIn((body["action_code"], body["action"]), CHALLENGE_ACTIONS)

    def test_every_action_has_a_code_and_text(self):
        from app.home_verification import CHALLENGE_ACTIONS, action_code_of
        codes = set()
        for code, text in CHALLENGE_ACTIONS:
            self.assertTrue(code and text)
            self.assertEqual(action_code_of(text), code)
            codes.add(code)
        self.assertEqual(len(codes), len(CHALLENGE_ACTIONS), "รหัสต้องไม่ซ้ำกัน")
        self.assertIsNone(action_code_of("ข้อความที่ไม่มีอยู่จริง"))

    def test_challenge_reports_whether_face_is_enrolled(self):
        with_face = self.client.post("/home-verifications/challenges", headers=self.headers(1))
        self.assertTrue(with_face.json()["face_enrolled"])
        without = self.client.post("/home-verifications/challenges", headers=self.headers(2))
        self.assertFalse(without.json()["face_enrolled"])

    def test_tiny_image_is_rejected(self):
        res = self.submit(photo=png_bytes(width=64, height=64))
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "evidence_invalid")

    # ---------- ส่งซ้ำ / เน็ตหลุด ----------

    def test_resending_the_same_request_returns_the_same_record(self):
        request_id = str(uuid.uuid4())
        challenge_id = self.challenge()
        photo = png_bytes(seed=31)
        first = self.submit(request_id=request_id, challenge_id=challenge_id, photo=photo)
        self.assertEqual(first.status_code, 200)
        # ส่งซ้ำทั้งดุ้นเหมือนแอปกดใหม่หลังเน็ตหลุด: challenge ถูกใช้แล้วและรูปซ้ำ
        # แต่ต้องได้รายการเดิม ไม่ใช่ error
        again = self.submit(request_id=request_id, challenge_id=challenge_id, photo=photo)
        self.assertEqual(again.status_code, 200, again.text)
        self.assertEqual(first.json()["id"], again.json()["id"])

        day = self.client.get("/home-verifications/me", headers=self.headers(1)).json()
        self.assertEqual(len(day["verifications"]), 1)

    def test_same_request_id_with_different_payload_is_a_conflict(self):
        request_id = str(uuid.uuid4())
        self.assertEqual(self.submit(request_id=request_id).status_code, 200)
        clash = self.submit(request_id=request_id, photo=png_bytes(seed=99))
        self.assertEqual(clash.status_code, 409)
        self.assertEqual(self.code(clash), "request_conflict")

    def test_lookup_by_request_id_recovers_a_lost_response(self):
        request_id = str(uuid.uuid4())
        created = self.submit(request_id=request_id).json()
        found = self.client.get(f"/home-verifications/requests/{request_id}",
                                headers=self.headers(1))
        self.assertEqual(found.status_code, 200)
        self.assertEqual(found.json()["id"], created["id"])

    def test_unknown_request_id_is_reported_as_not_found(self):
        res = self.client.get(f"/home-verifications/requests/{uuid.uuid4()}",
                              headers=self.headers(1))
        self.assertEqual(res.status_code, 404)
        self.assertEqual(self.code(res), "request_not_found")

    def test_request_lookup_is_scoped_to_the_owner(self):
        request_id = str(uuid.uuid4())
        self.submit(emp_id=1, request_id=request_id)
        res = self.client.get(f"/home-verifications/requests/{request_id}",
                              headers=self.headers(10))
        self.assertEqual(res.status_code, 404)

    # ---------- วันตามเวลาไทย ----------

    def test_daily_grouping_uses_server_thai_date_not_device(self):
        self.submit()
        today = self.client.get("/home-verifications/me", headers=self.headers(1)).json()
        yesterday = self.client.get(
            f"/home-verifications/me?date={(datetime.utcnow() + timedelta(hours=7)).date() - timedelta(days=1)}",
            headers=self.headers(1),
        ).json()
        self.assertTrue(today["verified"])
        self.assertFalse(yesterday["verified"])
        # ต้องบอกวันของ server มาด้วยเสมอ เพื่อให้แอปไม่ต้องเชื่อนาฬิกาเครื่องตัวเอง
        self.assertEqual(today["server_date"], today["date"])

    def test_yesterdays_record_does_not_verify_today(self):
        self.submit()
        with self.sessions() as db:
            row = db.query(HomeVerification).one()
            row.local_date = row.local_date - timedelta(days=1)
            row.verified_at = row.verified_at - timedelta(days=1)
            db.commit()
        today = self.client.get("/home-verifications/me", headers=self.headers(1)).json()
        self.assertFalse(today["verified"])

    def test_bad_date_format_is_rejected(self):
        res = self.client.get("/home-verifications/me?date=11-09-2026", headers=self.headers(1))
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.code(res), "date_invalid")

    # ---------- สิทธิ์ ----------

    def test_endpoints_require_authentication(self):
        self.assertEqual(self.client.post("/home-verifications/challenges").status_code, 401)
        self.assertEqual(self.client.get("/home-verifications/me").status_code, 401)


class EvidenceParsingTests(unittest.TestCase):
    """ตัวอ่านหัวไฟล์รูป — เขียนเองเพื่อไม่ต้องพึ่ง Pillow/OpenCV ที่ไม่ได้อยู่ใน requirements"""

    def test_reads_png_dimensions(self):
        from app.home_verification import image_info
        self.assertEqual(image_info(png_bytes(width=200, height=120)), ("png", 200, 120))

    def test_reads_jpeg_dimensions(self):
        from app.home_verification import image_info
        # JPEG ขั้นต่ำ: SOI + APP0 + SOF0 ที่ประกาศขนาด 480x640
        jpeg = (b"\xff\xd8"
                + b"\xff\xe0" + (16).to_bytes(2, "big") + b"JFIF\x00" + b"\x01\x01\x00\x00\x01\x00\x01\x00\x00"
                + b"\xff\xc0" + (17).to_bytes(2, "big") + b"\x08"
                + (640).to_bytes(2, "big") + (480).to_bytes(2, "big")
                + b"\x03\x01\x11\x00\x02\x11\x01\x03\x11\x01")
        self.assertEqual(image_info(jpeg), ("jpeg", 480, 640))

    def test_rejects_non_image_bytes(self):
        from app.home_verification import image_info
        self.assertIsNone(image_info(b"GIF89a" + b"\x00" * 64))
        self.assertIsNone(image_info(b""))
        self.assertIsNone(image_info(b"\x89PNG\r\n\x1a\n" + b"\x00" * 8))

    def test_fingerprint_tolerates_tiny_gps_jitter_but_not_a_new_photo(self):
        from app.home_verification import payload_fingerprint
        base = payload_fingerprint("c1", 13.8865664, 100.5066278, "abc")
        jitter = payload_fingerprint("c1", 13.88656641, 100.50662781, "abc")
        moved = payload_fingerprint("c1", 13.8875664, 100.5066278, "abc")
        other_photo = payload_fingerprint("c1", 13.8865664, 100.5066278, "def")
        self.assertEqual(base, jitter)
        self.assertNotEqual(base, moved)
        self.assertNotEqual(base, other_photo)


if __name__ == "__main__":
    unittest.main()
