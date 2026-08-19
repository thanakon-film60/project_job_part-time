"""ส่งสรุปการเข้างานประจำวันเข้ากลุ่ม LINE

รันเองก็ได้:
    venv\\Scripts\\python send_daily_summary.py            # สรุปของวันนี้
    venv\\Scripts\\python send_daily_summary.py 2026-08-14 # สรุปย้อนหลัง

ปกติจะถูกเรียกอัตโนมัติจาก Scheduled Task ทุกเย็น
(ติดตั้งด้วย deploy/line/install-daily-summary-task.ps1)
"""

import sys
from datetime import datetime, timedelta, timezone

from app.config import settings
from app.database import SessionLocal
from app.models import CheckIn, Employee
from app.notify_line import is_configured, push_text

TZ = timedelta(hours=settings.timezone_offset_hours)


def local_now() -> datetime:
    # Keep a naive value for compatibility with the existing SQLite columns,
    # but obtain UTC from the timezone-aware API (utcnow is deprecated).
    return datetime.now(timezone.utc).replace(tzinfo=None) + TZ


def build_summary(day: datetime.date) -> str:
    """สร้างข้อความสรุปของวันที่กำหนด (วันตามเวลาไทย)"""
    # ฐานข้อมูลเก็บเป็น UTC — แปลงช่วงวันไทยกลับเป็น UTC ก่อน query
    start_utc = datetime.combine(day, datetime.min.time()) - TZ
    end_utc = start_utc + timedelta(days=1)

    db = SessionLocal()
    try:
        employees = db.query(Employee).order_by(Employee.full_name).all()
        rows = (
            db.query(CheckIn)
            .filter(CheckIn.timestamp >= start_utc, CheckIn.timestamp < end_utc)
            .order_by(CheckIn.timestamp)
            .all()
        )
    finally:
        db.close()

    # จัดกลุ่มตามพนักงาน
    by_emp: dict[int, list[CheckIn]] = {}
    for r in rows:
        by_emp.setdefault(r.employee_id, []).append(r)

    lines = [f"📋 สรุปการเข้างาน {day.strftime('%d/%m/%Y')}", ""]

    present, absent = [], []
    for emp in employees:
        recs = by_emp.get(emp.id, [])
        if not recs:
            absent.append(emp)
            continue

        ins = [r for r in recs if r.kind == "in"]
        outs = [r for r in recs if r.kind == "out"]
        first_in = (ins[0].timestamp + TZ).strftime("%H:%M") if ins else "-"
        last_out = (outs[-1].timestamp + TZ).strftime("%H:%M") if outs else "-"
        office = next((r.office_name for r in recs if r.office_name), "-")
        present.append(f"  • {emp.full_name}  {first_in}–{last_out}  ({office})")

    lines.append(f"✅ มาทำงาน {len(present)} คน")
    lines.extend(present or ["  (ไม่มี)"])

    if absent:
        lines.append("")
        lines.append(f"⛔ ไม่มีบันทึก {len(absent)} คน")
        lines.extend(f"  • {e.full_name}" for e in absent)

    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) > 1:
        day = datetime.strptime(sys.argv[1], "%Y-%m-%d").date()
    else:
        day = local_now().date()

    text = build_summary(day)
    print(text)

    if not is_configured():
        print("\n[!] ยังไม่ได้ตั้งค่า LINE — แสดงผลอย่างเดียว ไม่ได้ส่ง")
        return 0

    ok = push_text(text)
    print("\n[OK] ส่งเข้ากลุ่มแล้ว" if ok else "\n[!] ส่งไม่สำเร็จ")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
