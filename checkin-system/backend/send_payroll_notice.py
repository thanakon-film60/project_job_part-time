"""ส่งสรุปรอบเงินเดือนเข้า LINE (ตัดรอบ / เริ่มรอบใหม่ / เงินเดือนออก)

ปกติถูกเรียกอัตโนมัติจาก Scheduled Task วันละ 2 รอบ (09:00 และ 18:00)
ติดตั้งด้วย deploy/line/install-payroll-task.ps1

สคริปต์เป็นคนตัดสินเองว่าวันนี้ควรส่งอะไร จึงตั้ง task เดียวรันทุกวันได้เลย
ไม่ต้องตั้ง task แยกสามอันตามวันที่ 26/27/28 — และส่งซ้ำไม่ได้เพราะทุกใบถูก
บันทึกไว้ในตาราง payroll_notices

รันเอง:
    venv\\Scripts\\python send_payroll_notice.py                  # ส่งที่ถึงกำหนดแล้ว
    venv\\Scripts\\python send_payroll_notice.py --status         # ดูรอบปัจจุบันเฉยๆ
    venv\\Scripts\\python send_payroll_notice.py --dry-run        # ดูข้อความโดยไม่ส่ง
    venv\\Scripts\\python send_payroll_notice.py --kind cutoff --dry-run
    venv\\Scripts\\python send_payroll_notice.py --date 2026-09-26 --dry-run
    venv\\Scripts\\python send_payroll_notice.py --kind payday --force   # ส่งซ้ำของจริง
"""

import argparse
import json
from datetime import datetime

from app.config import settings
from app.database import SessionLocal
from app.payroll import period_containing, period_in_focus, thai_date
from app.payroll_models import NOTICE_KINDS, NOTICE_LABELS
from app.payroll_service import (
    local_now,
    payroll_employees,
    run_due,
    send_notice,
    status,
)


def _print_status(db, now: datetime) -> None:
    info = status(db, now)
    current = info["current_period"]
    print("=== สถานะระบบเงินเดือน ===")
    print(f"เวลาที่ใช้คำนวณ : {info['now']} (เวลาไทย)")
    print(f"เปิดใช้งาน      : {'ใช่' if info['enabled'] else 'ไม่ (PAYROLL_ENABLED=false)'}")
    print(f"LINE พร้อมส่ง   : {'ใช่' if info['line_ready'] else 'ยัง — ตั้ง LINE_CHANNEL_ACCESS_TOKEN/LINE_TARGET_ID'}")
    if not info["separate_payroll_target"]:
        print("  [!] ยังไม่ได้ตั้ง PAYROLL_LINE_TARGET_ID — ข้อความเงินเดือนจะเข้าห้องเดียวกับแจ้งเข้างาน")
    print(f"ตัดรอบวันที่     : {info['cutoff_day']} · จ่ายวันที่ {info['payday']}")
    print(f"วิธีเฉลี่ยเงิน    : {info['prorate_basis']}")
    print(f"รอบปัจจุบัน      : {current['label']}")
    print(f"  ตัดรอบอีก     : {current['days_until_cutoff']} วัน")
    print(f"  เงินออกอีก    : {current['days_until_payday']} วัน ({thai_date(datetime.fromisoformat(current['payday']).date())})")

    print("\nพนักงานในระบบเงินเดือน:")
    if not info["employees_in_payroll"]:
        print("  (ยังไม่มีใคร — ตั้ง employees.base_salary หรือ PAYROLL_DEFAULT_SALARY)")
    for emp in info["employees_in_payroll"]:
        start = emp["start_date"] or "ไม่ได้ตั้งวันเริ่มงาน"
        print(f"  • {emp['name']} ({emp['employee_code']})  ฿{emp['base_salary']:,.0f}/เดือน  เริ่ม {start}")

    print("\nถึงกำหนดส่งตอนนี้:")
    if not info["due_now"]:
        print("  (ไม่มี)")
    for item in info["due_now"]:
        print(f"  • {NOTICE_LABELS.get(item['kind'], item['kind'])} ของรอบจ่าย {item['period']}")


def _print_report(report: dict) -> int:
    if report.get("reason"):
        print(f"[!] {report['reason']}")

    if not report["due"]:
        print("ยังไม่ถึงกำหนดส่งอะไรในตอนนี้")
        return 0

    for item in report["due"]:
        label = NOTICE_LABELS.get(item["kind"], item["kind"])
        print(f"\n=== {label} — รอบจ่าย {item['period']} (กำหนดส่ง {item['scheduled_at']}) ===")

    failures = 0
    for result in report["results"]:
        head = f"{result['name']} [{NOTICE_LABELS.get(result['kind'], result['kind'])}]"
        if result.get("text"):
            print(f"\n--- ข้อความที่จะส่งถึง {head} ---")
            print(result["text"])
        if result["sent"]:
            print(f"[OK] ส่งให้ {head} แล้ว")
        else:
            reason = result.get("reason", "ไม่ทราบสาเหตุ")
            print(f"[--] ไม่ได้ส่งให้ {head}: {reason}")
            # "ส่งไปแล้ว" กับ dry-run ไม่ใช่ความผิดพลาด ไม่ควรทำให้ exit code เป็น 1
            if "ส่งไปแล้ว" not in reason and "dry-run" not in reason:
                failures += 1

    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="ส่งสรุปรอบเงินเดือนเข้า LINE",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--status", action="store_true", help="ดูสถานะรอบปัจจุบันอย่างเดียว ไม่ส่ง")
    parser.add_argument("--kind", choices=NOTICE_KINDS, help="บังคับส่งเฉพาะชนิดนี้")
    parser.add_argument("--date", help="สมมติว่าวันนี้คือวันที่นี้ (YYYY-MM-DD) สำหรับทดสอบ")
    parser.add_argument("--dry-run", action="store_true", help="สร้างข้อความให้ดูแต่ไม่ส่งจริง")
    parser.add_argument("--force", action="store_true", help="ส่งซ้ำแม้เคยส่งรอบนี้ไปแล้ว")
    parser.add_argument("--json", action="store_true", help="คืนผลเป็น JSON (ให้สคริปต์อื่นอ่านต่อ)")
    args = parser.parse_args()

    if args.date:
        day = datetime.strptime(args.date, "%Y-%m-%d").date()
        # ใช้ปลายวันเพื่อให้ข้อความที่ตั้งเวลาไว้ตอนเย็นของวันนั้นถึงกำหนดด้วย
        now = datetime.combine(day, datetime.max.time().replace(microsecond=0))
    else:
        now = local_now()

    db = SessionLocal()
    try:
        if args.status:
            _print_status(db, now)
            return 0

        # --kind + --force = สั่งส่งใบนั้นตรงๆ ไม่ต้องรอให้ถึงกำหนด
        # (ใช้ตอนอยากดูหน้าตาการ์ดก่อนถึงวันจริง)
        if args.kind and args.force:
            # cycle_start พูดถึงรอบที่กำลังเดิน ส่วน cutoff/payday พูดถึงรอบที่เงินกำลังจะออก
            today = now.date()
            period = (
                period_containing(today)
                if args.kind == "cycle_start"
                else period_in_focus(today)
            )
            employees = payroll_employees(db)
            if not employees:
                print("[!] ไม่มีพนักงานที่ตั้งเงินเดือนไว้")
                return 1
            report = {
                "due": [
                    {
                        "kind": args.kind,
                        "period": period.key,
                        "scheduled_at": now.isoformat(timespec="minutes"),
                    }
                ],
                "results": [
                    send_notice(
                        db, emp, args.kind, period, force=True, dry_run=args.dry_run
                    )
                    for emp in employees
                ],
            }
        else:
            report = run_due(
                db,
                now=now,
                force=args.force,
                dry_run=args.dry_run,
                only_kind=args.kind,
            )

        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
            return 0
        return _print_report(report)
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
