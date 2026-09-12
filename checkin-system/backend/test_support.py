"""python -m unittest test_support -v -- ใช้ SQLite ในหน่วยความจำ ไม่แตะฐานข้อมูลจริง

คุมสองเรื่องหลักที่พังแล้วอันตราย:
  1. ใครเข้าห้องได้บ้าง (ลิงก์คือกุญแจ ห้องหมดอายุ/ปิดแล้วต้องเข้าไม่ได้จริง)
  2. ห้องส่งต่อได้เฉพาะข้อความที่อนุญาต ไม่กลายเป็นช่องส่งอะไรก็ได้ระหว่างคนนอก
"""
import unittest
from datetime import datetime, timedelta

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import get_db
from app.models import Employee
from app.routers import support
from app.security import create_access_token
from app.support_models import SupportSession


class SupportTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        Employee.__table__.create(self.engine)
        SupportSession.__table__.create(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        with self.sessions() as db:
            db.add(Employee(id=1, employee_code="T1", full_name="ผู้ช่วยไอที",
                            email="t1@example.invalid", hashed_password="x", is_manager=True))
            db.add(Employee(id=2, employee_code="T2", full_name="พนักงานอื่น",
                            email="t2@example.invalid", hashed_password="x", is_manager=False))
            db.commit()

        app = FastAPI()
        app.include_router(support.router)

        def test_db():
            with self.sessions() as db:
                yield db

        app.dependency_overrides[get_db] = test_db
        # WebSocket เปิด session เองไม่ผ่าน Depends (จะได้ไม่ถือ connection ค้างทั้งสาย)
        # จึงต้องสลับ SessionLocal ให้ชี้มาที่ฐานข้อมูลทดสอบด้วย
        self._real_session_local = support.SessionLocal
        support.SessionLocal = self.sessions
        support._rooms.clear()
        self.client = TestClient(app)

    def tearDown(self):
        self.client.close()
        support.SessionLocal = self._real_session_local
        support._rooms.clear()
        self.engine.dispose()

    # ------------------------------------------------------------ ตัวช่วย
    def headers(self, code="T1"):
        return {"Authorization": f"Bearer {create_access_token(code)}"}

    def token(self, code="T1"):
        return create_access_token(code)

    def open_room(self, title="ปริ้นเตอร์เสีย"):
        res = self.client.post("/support/sessions", headers=self.headers(),
                               json={"title": title, "guest_label": "คุณสมชาย"})
        self.assertEqual(res.status_code, 200, res.text)
        return res.json()

    def set_expiry(self, code, when):
        with self.sessions() as db:
            row = db.query(SupportSession).filter(SupportSession.code == code).first()
            row.expires_at = when
            db.commit()

    # ------------------------------------------------------------ สิทธิ์
    def test_auth_required(self):
        self.assertEqual(self.client.post("/support/sessions", json={}).status_code, 401)
        self.assertEqual(self.client.get("/support/sessions").status_code, 401)
        self.assertEqual(self.client.post("/support/sessions/abc/end").status_code, 401)

    def test_only_owner_sees_or_closes_a_room(self):
        room = self.open_room()
        # คนอื่นที่ล็อกอินอยู่ก็ต้องมองไม่เห็นห้องของเรา (ตอบ 404 ไม่ใช่ 403 จะได้ไม่ยืนยันว่ามีห้องนี้)
        self.assertEqual(
            self.client.get(f"/support/sessions/{room['code']}", headers=self.headers("T2")).status_code, 404
        )
        self.assertEqual(
            self.client.post(f"/support/sessions/{room['code']}/end", headers=self.headers("T2")).status_code, 404
        )
        self.assertEqual(self.client.get("/support/sessions", headers=self.headers("T2")).json()["sessions"], [])

    def test_room_limit(self):
        for _ in range(support.settings.support_max_open_sessions):
            self.open_room()
        res = self.client.post("/support/sessions", headers=self.headers(), json={})
        self.assertEqual(res.status_code, 409)

    # ------------------------------------------------------------ ฝั่งผู้ใช้
    def test_guest_info_shows_who_is_asking(self):
        room = self.open_room()
        info = self.client.get(f"/support/guest/{room['code']}").json()
        self.assertTrue(info["joinable"])
        # ผู้ใช้ต้องเห็นชื่อคนขอ ก่อนตัดสินใจเปิดกล้องให้
        self.assertEqual(info["host_name"], "ผู้ช่วยไอที")
        self.assertEqual(self.client.get("/support/guest/ไม่มีจริง").status_code, 404)

    def test_expired_link_is_dead(self):
        room = self.open_room()
        self.set_expiry(room["code"], datetime.utcnow() - timedelta(minutes=1))
        info = self.client.get(f"/support/guest/{room['code']}").json()
        self.assertFalse(info["joinable"])
        with self.assertRaises(Exception):
            with self.client.websocket_connect(f"/support/ws/{room['code']}?role=guest"):
                pass

    def test_closed_room_is_dead(self):
        room = self.open_room()
        self.client.post(f"/support/sessions/{room['code']}/end", headers=self.headers())
        self.assertFalse(self.client.get(f"/support/guest/{room['code']}").json()["joinable"])
        with self.assertRaises(Exception):
            with self.client.websocket_connect(f"/support/ws/{room['code']}?role=guest"):
                pass

    # ------------------------------------------------------------ WebSocket
    def test_host_socket_needs_a_valid_owner_token(self):
        room = self.open_room()
        for query in ("role=host", "role=host&token=ไม่ใช่โทเค็น",
                      f"role=host&token={self.token('T2')}", "role=คนอื่น"):
            with self.assertRaises(Exception, msg=query):
                with self.client.websocket_connect(f"/support/ws/{room['code']}?{query}"):
                    pass

    def test_relay_between_the_two_sides(self):
        room = self.open_room()
        url = f"/support/ws/{room['code']}"
        with self.client.websocket_connect(f"{url}?role=host&token={self.token()}") as host:
            ready = host.receive_json()
            self.assertEqual(ready["type"], "ready")
            self.assertFalse(ready["peer_online"])

            with self.client.websocket_connect(f"{url}?role=guest") as guest:
                self.assertTrue(guest.receive_json()["peer_online"])
                self.assertEqual(host.receive_json(),
                                 {"type": "peer", "role": "guest", "state": "joined"})

                stroke = {"id": "s1", "tool": "circle", "color": "#ff3b30",
                          "width": 0.9, "points": [[0.2, 0.3], [0.6, 0.7]]}
                host.send_json({"type": "draw", "stroke": stroke})
                received = guest.receive_json()
                self.assertEqual(received["stroke"], stroke)
                self.assertEqual(received["from"], "host")  # บอกเสมอว่ามาจากฝั่งไหน

                # ping ตอบกลับที่ตัวเอง ไม่ส่งต่อไปกวนอีกฝั่ง
                guest.send_json({"type": "ping"})
                self.assertEqual(guest.receive_json()["type"], "pong")

            self.assertEqual(host.receive_json(),
                             {"type": "peer", "role": "guest", "state": "left"})

        with self.sessions() as db:
            row = db.query(SupportSession).filter(SupportSession.code == room["code"]).first()
            self.assertEqual(row.status, "active")
            self.assertIsNotNone(row.guest_joined_at)

    def test_unlisted_message_types_are_dropped(self):
        room = self.open_room()
        url = f"/support/ws/{room['code']}"
        with self.client.websocket_connect(f"{url}?role=host&token={self.token()}") as host:
            host.receive_json()
            with self.client.websocket_connect(f"{url}?role=guest") as guest:
                guest.receive_json()
                host.receive_json()

                host.send_json({"type": "อะไรก็ไม่รู้", "payload": "x"})
                host.send_json({"type": "not-in-the-list"})
                host.send_json({"type": "clear"})
                # ถ้าสองอันแรกหลุดไปได้ ตัวที่อ่านได้จะไม่ใช่ clear
                self.assertEqual(guest.receive_json()["type"], "clear")

    def test_oversized_message_is_dropped(self):
        room = self.open_room()
        url = f"/support/ws/{room['code']}"
        with self.client.websocket_connect(f"{url}?role=host&token={self.token()}") as host:
            host.receive_json()
            with self.client.websocket_connect(f"{url}?role=guest") as guest:
                guest.receive_json()
                host.receive_json()
                host.send_json({"type": "freeze", "image": "x" * (support.MAX_MESSAGE_CHARS + 10)})
                host.send_json({"type": "clear"})
                self.assertEqual(guest.receive_json()["type"], "clear")

    def test_reopening_the_same_role_kicks_the_stale_socket(self):
        """รีเฟรชหน้าแล้วต้องเข้าห้องเดิมได้ทันที ไม่ใช่ติดว่ามีคนอยู่แล้ว"""
        room = self.open_room()
        url = f"/support/ws/{room['code']}?role=host&token={self.token()}"
        with self.client.websocket_connect(url) as first:
            first.receive_json()
            with self.client.websocket_connect(url) as second:
                self.assertEqual(second.receive_json()["type"], "ready")
                self.assertEqual(first.receive_json()["type"], "replaced")

    def test_lone_peer_is_told_nobody_is_there(self):
        room = self.open_room()
        with self.client.websocket_connect(
            f"/support/ws/{room['code']}?role=host&token={self.token()}"
        ) as host:
            host.receive_json()
            host.send_json({"type": "clear"})
            self.assertEqual(host.receive_json(),
                             {"type": "peer", "role": "guest", "state": "offline"})

    def test_ice_servers_are_public(self):
        # ฝั่งผู้ใช้ไม่มีบัญชี จึงต้องดึงค่านี้ได้โดยไม่ต้องล็อกอิน
        res = self.client.get("/support/ice-servers")
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.json()["ice_servers"])


if __name__ == "__main__":
    unittest.main()
