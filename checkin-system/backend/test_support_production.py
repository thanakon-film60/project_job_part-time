"""ทดสอบห้องช่วยเหลือระยะไกลบน production จริง ด้วยเบราว์เซอร์สองฝั่ง

    python test_support_production.py
    python test_support_production.py --origin https://thanakronpart-time.com

เป็นตัวเดียวที่เดินเส้นทางเดียวกับผู้ใช้จริงทุกขั้น: Cloudflare -> tunnel -> backend
จึงใช้พิสูจน์ว่า "เปิดใช้จริงแล้วใช้งานได้" ไม่ใช่แค่ "โค้ดถูก"

⚠️ แตะฐานข้อมูล production จริง — สร้างห้องทดสอบ 1 ห้องแล้วลบทิ้งเมื่อจบ
   ไม่แตะข้อมูลพนักงาน การลงเวลา หรือเงินเดือนเลย
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

# pydantic-settings อ่าน .env เทียบกับโฟลเดอร์ปัจจุบัน — ต้องย้ายมาก่อนแตะ app.config
os.chdir(HERE)

DEFAULT_ORIGIN = "https://thanakronpart-time.com"


def resolve_origin() -> str:
    if "--origin" in sys.argv:
        index = sys.argv.index("--origin")
        if index + 1 < len(sys.argv):
            return sys.argv[index + 1].rstrip("/")
    return DEFAULT_ORIGIN


def main() -> int:
    origin = resolve_origin()
    print(f"ทดสอบกับ {origin}\n")

    from app.database import SessionLocal
    from app.models import Employee
    from app.security import create_access_token
    from app.support_models import SupportSession

    db = SessionLocal()
    try:
        host = db.query(Employee).filter(Employee.is_manager.is_(True)).first()
        if host is None:
            print("ไม่พบบัญชีหัวหน้าไว้ใช้ทดสอบ")
            return 1
        print(f"ใช้บัญชี {host.employee_code} ({host.full_name}) เปิดห้องทดสอบ")

        employee_json = json.dumps(
            {"id": host.id, "employee_code": host.employee_code,
             "full_name": host.full_name, "is_manager": True},
            ensure_ascii=False,
        )

        with tempfile.TemporaryDirectory(prefix="support-prod-") as temp:
            env = {
                **os.environ,
                "SUPPORT_PROD_ORIGIN": origin,
                "SUPPORT_PROD_TOKEN": create_access_token(host.employee_code),
                "SUPPORT_PROD_EMPLOYEE": employee_json,
                "SUPPORT_PROD_ARTIFACTS": temp,
                "NODE_PATH": str(ROOT / "frontend" / "node_modules"),
            }
            result = subprocess.run(
                ["node", str(ROOT / "frontend" / "tests" / "support-production.cjs")],
                env=env, capture_output=True, text=True, encoding="utf-8",
            )
            print(result.stdout, end="")
            if result.stderr.strip():
                print(result.stderr, end="")

            # ห้องทดสอบต้องถูกลบทิ้งเสมอ แม้เทสจะพังกลางทาง ไม่งั้นลิงก์ค้างอยู่ในระบบจริง
            code = ""
            for line in result.stdout.splitlines():
                if line.startswith("ROOM_CODE="):
                    code = line.split("=", 1)[1].strip()
            if code:
                row = db.query(SupportSession).filter(SupportSession.code == code).first()
                if row is not None:
                    db.delete(row)
                    db.commit()
                    print(f"\nลบห้องทดสอบ {code} ออกจากฐานข้อมูลแล้ว")

            if result.returncode == 0:
                keep = HERE / "storage" / "logs"
                keep.mkdir(parents=True, exist_ok=True)
                for name in ("production-host.png", "production-guest.png"):
                    shot = Path(temp) / name
                    if shot.exists():
                        (keep / name).write_bytes(shot.read_bytes())
                print(f"ภาพหน้าจอเก็บไว้ที่ {keep}")

            left = db.query(SupportSession).count()
            print(f"ห้องที่เหลือในระบบจริง: {left}")
            return result.returncode
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
