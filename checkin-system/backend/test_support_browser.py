"""เปิดเซิร์ฟเวอร์ชั่วคราว + ฐานข้อมูลแยก แล้วให้เบราว์เซอร์จริงสองฝั่งคุยกันผ่าน WebRTC

    python test_support_browser.py

ต่างจาก test_support.py ตรงที่ตัวนั้นตรวจ "ฝั่งเซิร์ฟเวอร์" อย่างเดียว
ส่วนตัวนี้ตรวจของจริงทั้งเส้น: หน้าเว็บ -> WebSocket -> จับมือ SDP/ICE ->
ส่งภาพจากกล้อง (ปลอม) -> วาดเส้นแล้วอีกฝั่งเห็น

ต้องมี: playwright (npm i -D playwright) + Microsoft Edge บนเครื่อง
ไม่แตะฐานข้อมูลจริงหรือ tunnel ใด ๆ — ใช้ SQLite ในโฟลเดอร์ชั่วคราวที่ลบทิ้งเมื่อจบ
"""
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / "backend"))

import uvicorn
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import get_db
from app.models import Employee
from app.routers import support
from app.security import create_access_token
from app.support_models import SupportSession

DIST = root / "frontend" / "dist"

USERS = [
    dict(id=10, employee_code="BOSS10", full_name="หัวหน้าทดสอบ",
         email="boss@example.invalid", is_manager=True),
    dict(id=1, employee_code="TEST1", full_name="พนักงานทดสอบ",
         email="one@example.invalid", is_manager=False),
]


def build_app(sessions):
    app = FastAPI()

    def test_db():
        with sessions() as db:
            yield db

    app.dependency_overrides[get_db] = test_db
    app.include_router(support.router)

    # WebSocket ของ support เปิด session เองไม่ผ่าน Depends (จะได้ไม่ถือ connection
    # ค้างทั้งสาย) จึงต้องสลับ SessionLocal ให้ชี้มาฐานข้อมูลทดสอบด้วย
    support.SessionLocal = sessions

    @app.get("/__test/session/{user_id}")
    def seed_session(user_id: int):
        user = next(u for u in USERS if u["id"] == user_id)
        return {"employee": user, "token": create_access_token(user["employee_code"])}

    # หน้าเว็บเรียกพวกนี้ตอนโหลด — ตอบค่าว่างพอให้หน้าไม่พัง
    @app.get("/reports/geofence")
    def geofence():
        return {"offices": [], "work_schedule": {"work_start": "08:30", "work_end": "17:30",
                                                 "enabled": True, "late_grace_minutes": 0,
                                                 "early_leave_grace_minutes": 0}}

    @app.get("/checkins/me")
    @app.get("/faces/me")
    def empty_list():
        return []

    @app.get("/chat/contacts")
    def contacts():
        return {"contacts": []}

    @app.get("/reports/team-calendar")
    def calendar():
        return {"days": []}

    @app.get("/app/info")
    @app.get("/boss-app/info")
    def app_info():
        return {"available": False}

    # React Router: path ของหน้าเว็บต้องคืน index.html ไม่ใช่ 404
    @app.get("/it-support")
    @app.get("/remote-help/{code}")
    def spa(code: str = ""):
        return FileResponse(DIST / "index.html")

    app.mount("/", StaticFiles(directory=DIST, html=True), name="static")
    return app


def main() -> int:
    if not (DIST / "index.html").exists():
        print("ไม่พบ frontend/dist — สั่ง npm run build ก่อน")
        return 1

    with tempfile.TemporaryDirectory(prefix="checkin-support-browser-") as temp:
        engine = create_engine("sqlite://", connect_args={"check_same_thread": False},
                               poolclass=StaticPool)
        Employee.__table__.create(engine)
        SupportSession.__table__.create(engine)
        sessions = sessionmaker(bind=engine)
        with sessions() as db:
            for user in USERS:
                db.add(Employee(**user, hashed_password="test-only"))
            db.commit()

        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        server = uvicorn.Server(uvicorn.Config(build_app(sessions), log_level="error"))
        thread = threading.Thread(target=lambda: server.run(sockets=[sock]), daemon=True)
        thread.start()
        for _ in range(200):
            if server.started:
                break
            time.sleep(0.05)

        origin = f"http://127.0.0.1:{port}"
        print(f"เซิร์ฟเวอร์ทดสอบ: {origin}\n")
        env = {
            **os.environ,
            "SUPPORT_TEST_ORIGIN": origin,
            "SUPPORT_TEST_ARTIFACTS": temp,
            # หา playwright จาก node_modules ของ frontend ไม่ต้องลง global
            "NODE_PATH": str(root / "frontend" / "node_modules"),
        }
        try:
            result = subprocess.run(
                ["node", str(root / "frontend" / "tests" / "support-browser.cjs")],
                env=env,
            )
        finally:
            server.should_exit = True
            thread.join(5)
            engine.dispose()

        # เก็บภาพหน้าจอไว้ดูก่อนโฟลเดอร์ชั่วคราวถูกลบ
        if result.returncode == 0:
            keep = Path(__file__).resolve().parent / "storage" / "logs"
            keep.mkdir(parents=True, exist_ok=True)
            for name in ("support-host.png", "support-guest.png"):
                shot = Path(temp) / name
                if shot.exists():
                    (keep / name).write_bytes(shot.read_bytes())
            print(f"\nภาพหน้าจอเก็บไว้ที่ {keep}")
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
