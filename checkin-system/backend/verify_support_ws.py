"""ตรวจว่า WebSocket ของห้องช่วยเหลือระยะไกลวิ่งผ่าน IIS ได้จริงไหม แล้วเขียนผลลงไฟล์

    python verify_support_ws.py

ทำไมต้องมี: IIS จะส่งต่อ WebSocket ได้ก็ต่อเมื่อเปิดฟีเจอร์ Web-WebSockets ไว้แล้ว
ถ้าไม่ได้เปิด หน้าเว็บจะค้างที่ "กำลังเชื่อมต่อ..." เฉย ๆ โดยไม่มี error ให้เห็นใน log ที่ไหนเลย
— อาการเดียวกับตอน backend ล่ม ทำให้ไล่หาสาเหตุยากมากถ้าไม่มีตัวตรวจแบบนี้

ตัวสคริปต์สร้างห้องทดสอบ 1 ห้องแล้วลบทิ้งเมื่อเสร็จ ไม่แตะข้อมูลพนักงานหรือการลงเวลาใด ๆ
"""
import asyncio
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

REPORT = HERE / "storage" / "logs" / "remote-support-check.txt"
IIS_HOST = "localhost"
BACKEND = "127.0.0.1:8001"
# เผื่อเวลาให้ backend ตื่นหลังเครื่องบูต (Scheduled Task เริ่มพร้อมกับบริการอื่นอีกหลายตัว)
WAIT_BACKEND_SECONDS = 180

lines: list[str] = []


def log(message: str) -> None:
    print(message)
    lines.append(message)


def wait_for_backend() -> bool:
    deadline = time.time() + WAIT_BACKEND_SECONDS
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://{BACKEND}/health", timeout=5):
                return True
        except (urllib.error.URLError, OSError):
            time.sleep(5)
    return False


def api(path: str, token: str | None = None, data: dict | None = None) -> dict:
    body = json.dumps(data).encode() if data is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"http://{IIS_HOST}{path}", data=body, headers=headers,
        method="POST" if data is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read())


async def can_connect(url: str) -> tuple[bool, str]:
    import websockets

    try:
        async with websockets.connect(url, open_timeout=20) as ws:
            ready = json.loads(await asyncio.wait_for(ws.recv(), timeout=20))
            return True, f"ตอบกลับ {ready.get('type')} role={ready.get('role')}"
    except Exception as exc:
        return False, f"{type(exc).__name__}: {exc}"


def main() -> int:
    log(f"ตรวจระบบช่วยเหลือระยะไกล — {datetime.now():%Y-%m-%d %H:%M:%S}")
    log("=" * 60)

    if not wait_for_backend():
        log(f"[ไม่ผ่าน] backend ที่ {BACKEND} ไม่ตอบภายใน {WAIT_BACKEND_SECONDS} วินาที")
        log("  ตรวจด้วย: Get-ScheduledTaskInfo -TaskName MardodiCheckinAPI")
        return 1
    log(f"[ผ่าน] backend ที่ {BACKEND} ตอบแล้ว")

    from app.database import SessionLocal
    from app.models import Employee
    from app.security import create_access_token
    from app.support_models import SupportSession

    db = SessionLocal()
    code = None
    token = None
    try:
        host = db.query(Employee).filter(Employee.is_manager.is_(True)).first()
        if host is None:
            log("[ไม่ผ่าน] ไม่พบบัญชีหัวหน้าไว้ใช้ทดสอบ")
            return 1
        token = create_access_token(host.employee_code)

        try:
            api("/support/ice-servers")
            log("[ผ่าน] IIS ส่งต่อ /support/* ไป backend แล้ว")
        except Exception as exc:
            log(f"[ไม่ผ่าน] IIS ไม่ส่งต่อ /support/*: {exc}")
            log("  แก้: เติม support ในกฎ ProxyToBackend ของ web.config")
            return 1

        code = api("/support/sessions", token, {"title": "[ตรวจระบบอัตโนมัติ]"})["code"]

        direct_ok, direct_note = asyncio.run(
            can_connect(f"ws://{BACKEND}/support/ws/{code}?role=guest")
        )
        log(f"[{'ผ่าน' if direct_ok else 'ไม่ผ่าน'}] WebSocket ตรงไป backend — {direct_note}")

        iis_ok, iis_note = asyncio.run(
            can_connect(f"ws://{IIS_HOST}/support/ws/{code}?role=guest")
        )
        log(f"[{'ผ่าน' if iis_ok else 'ไม่ผ่าน'}] WebSocket ผ่าน IIS — {iis_note}")

        log("=" * 60)
        if iis_ok:
            log("สรุป: ระบบช่วยเหลือระยะไกลพร้อมใช้งานเต็มรูปแบบ")
            log("  เปิดเมนู 'ช่วยเหลือระยะไกล' แล้วสร้างห้องได้เลย")
            return 0
        if direct_ok:
            log("สรุป: backend ปกติ แต่ IIS ยังส่งต่อ WebSocket ไม่ได้")
            log("  แก้: Install-WindowsFeature Web-WebSockets แล้ว restart เครื่อง")
            log("  ตรวจสถานะ: Get-WindowsFeature Web-WebSockets  (ต้องเป็น Installed)")
            return 1
        log("สรุป: ต่อ WebSocket ไม่ได้ทั้งสองทาง — ดูรายละเอียดด้านบน")
        return 1
    finally:
        # เก็บกวาดห้องทดสอบเสมอ แม้ระหว่างตรวจจะพังกลางทาง
        if code:
            try:
                api(f"/support/sessions/{code}/end", token, {})
            except Exception:
                pass
            row = db.query(SupportSession).filter(SupportSession.code == code).first()
            if row is not None:
                db.delete(row)
                db.commit()
        db.close()


if __name__ == "__main__":
    try:
        exit_code = main()
    except Exception as error:  # เขียนรายงานให้ได้เสมอ ถึงจะพังแบบไม่คาดคิด
        log(f"[ไม่ผ่าน] สคริปต์ล้มเหลว: {type(error).__name__}: {error}")
        exit_code = 1

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\nเขียนผลไว้ที่ {REPORT}")
    sys.exit(exit_code)
