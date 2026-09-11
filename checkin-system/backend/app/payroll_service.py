"""เชื่อมการคำนวณเงินเดือนเข้ากับฐานข้อมูลและ LINE

แบ่งหน้าที่ชัดเจน:
    payroll.py          คณิตศาสตร์ล้วน ไม่รู้จัก DB
    line_flex.py        หน้าตาการ์ด
    payroll_service.py  ไฟล์นี้ — ดึงข้อมูลจริง ตัดสินว่าถึงเวลาส่งหรือยัง แล้วส่ง

"ถึงเวลาส่งหรือยัง" ไม่ได้ดูแค่ว่าวันนี้วันที่เท่าไร แต่ดูย้อนหลังได้ตาม
PAYROLL_NOTICE_CATCHUP_HOURS ด้วย เพราะเซิร์ฟเวอร์เครื่องนี้ดับ/รีบูตได้
ถ้าเช็คแค่ "วันนี้ใช่วันที่ 26 ไหม" แล้วเครื่องดับข้ามวัน ข้อความรอบนั้นจะหายไปเลย
"""

import logging
from datetime import date, datetime, time, timedelta, timezone

from sqlalchemy.orm import Session

from .config import settings
from .geofence import location_category, office_by_name
from .line_flex import alt_text, cutoff_bubble, cycle_start_bubble, payday_bubble, summary_text
from .models import CheckIn, Employee
from .notify_line import is_configured, push_flex
from .payroll import (
    PayrollPeriod,
    PayrollSummary,
    build_summary,
    next_period,
    period_containing,
    previous_period,
    projected_full_period,
)
from .payroll_models import (
    NOTICE_CUTOFF,
    NOTICE_CYCLE_START,
    NOTICE_KINDS,
    NOTICE_PAYDAY,
    PayrollNotice,
)
from .work_schedule import evaluate_attendance

log = logging.getLogger("payroll")

LOCAL_OFFSET = timedelta(hours=settings.timezone_offset_hours)


def local_now() -> datetime:
    """เวลาไทยแบบ naive — ให้ตรงกับที่ DB เก็บ (UTC naive) บวกออฟเซ็ตแล้ว"""
    return datetime.now(timezone.utc).replace(tzinfo=None) + LOCAL_OFFSET


def _to_utc(local_dt: datetime) -> datetime:
    return local_dt - LOCAL_OFFSET


def _to_local(utc_dt: datetime) -> datetime:
    return utc_dt + LOCAL_OFFSET


# ---------------------------------------------------------------------------
# พนักงานที่อยู่ในระบบเงินเดือน
# ---------------------------------------------------------------------------


def salary_of(employee: Employee) -> float:
    """เงินเดือนของพนักงานคนนี้ — ค่ารายคนมาก่อนค่า default ใน .env

    คืน 0 = ไม่อยู่ในระบบเงินเดือน (ไม่คำนวณ ไม่แจ้งเตือน) เพื่อให้ค่าเริ่มต้น
    ปลอดภัย: ไม่มีใครถูกส่งตัวเลขเงินเดือนเข้า LINE โดยที่ยังไม่ได้ตั้งค่า
    """
    personal = getattr(employee, "base_salary", None)
    if personal:
        return float(personal)
    # ค่า default คือการเหมารวมว่า "ทุกคนได้เท่านี้" ซึ่งไม่เคยหมายถึงบัญชีหัวหน้า
    # (เกณฑ์เดียวกับ send_daily_summary.py ที่ไม่นับบัญชี Boss เป็นพนักงาน)
    # หัวหน้าที่ต้องอยู่ในระบบเงินเดือนจริงๆ ให้ตั้ง base_salary รายคนแทน
    if employee.is_manager:
        return 0.0
    return float(settings.payroll_default_salary or 0)


def payroll_employees(db: Session) -> list[Employee]:
    """พนักงานที่มีเงินเดือนตั้งไว้ เรียงตามชื่อ"""
    employees = db.query(Employee).order_by(Employee.full_name).all()
    return [emp for emp in employees if salary_of(emp) > 0]


# ---------------------------------------------------------------------------
# ดึงการลงเวลาจริงของรอบ
# ---------------------------------------------------------------------------


def attendance_in_period(
    db: Session, employee_id: int, period: PayrollPeriod
) -> tuple[set[date], set[date], int]:
    """(วันที่มาทำงาน, วันที่มาสาย, นาทีสายรวม) ของพนักงานคนนี้ในรอบที่กำหนด

    นับเฉพาะการลงเวลา `in` ที่อยู่ในเขตและไม่ใช่จุดประเภทบ้าน — ใช้เกณฑ์
    เดียวกับข้อความแจ้งเข้างานและปฏิทินบนเว็บ เพื่อไม่ให้ตัวเลขขัดกันเอง

    วันหนึ่งนับครั้งเดียวแม้กดหลายรอบ และ "สาย" ยึดการกดเข้างาน**ครั้งแรก**
    ของวันนั้น (กดซ้ำตอนบ่ายต้องไม่ทำให้กลายเป็นสาย)
    """
    start_utc = _to_utc(datetime.combine(period.start, time.min))
    end_utc = _to_utc(datetime.combine(period.end, time.max))

    rows = (
        db.query(CheckIn)
        .filter(
            CheckIn.employee_id == employee_id,
            CheckIn.kind == "in",
            CheckIn.timestamp >= start_utc,
            CheckIn.timestamp <= end_utc,
        )
        .order_by(CheckIn.timestamp)
        .all()
    )

    first_in: dict[date, tuple[datetime, dict | None]] = {}
    for row in rows:
        office = office_by_name(row.office_name)
        if location_category(office) == "home":
            continue  # อยู่บ้าน = ไม่ได้ไปทำงาน
        if not row.within_geofence:
            continue  # นอกเขต = ระบบไม่รับเป็นการเข้างานอยู่แล้ว
        local_dt = _to_local(row.timestamp)
        day = local_dt.date()
        if day not in first_in or local_dt < first_in[day][0]:
            first_in[day] = (local_dt, office)

    present: set[date] = set(first_in)
    late: set[date] = set()
    late_minutes = 0
    for day, (local_dt, office) in first_in.items():
        verdict = evaluate_attendance("in", local_dt, office)
        if verdict.is_late:
            late.add(day)
            late_minutes += verdict.minutes

    return present, late, late_minutes


def summary_for(
    db: Session,
    employee: Employee,
    period: PayrollPeriod,
    as_of: date | None = None,
) -> PayrollSummary:
    """สรุปเงินของพนักงานหนึ่งคนในรอบหนึ่ง (ดึงการลงเวลาจริงมาให้แล้ว)"""
    present, late, late_minutes = attendance_in_period(db, employee.id, period)
    return build_summary(
        period=period,
        employee_name=(employee.full_name or "").strip() or employee.employee_code,
        base_salary=salary_of(employee),
        employment_start=employee.start_date,
        present_days=present,
        late_days=late,
        late_minutes=late_minutes,
        as_of=as_of or min(local_now().date(), period.end),
    )


# ---------------------------------------------------------------------------
# ถึงเวลาส่งหรือยัง
# ---------------------------------------------------------------------------


def _scheduled_moments(today: date) -> dict[str, list[tuple[datetime, PayrollPeriod]]]:
    """เวลาที่ข้อความแต่ละแบบ "ควรถูกส่ง" ของรอบล่าสุดๆ

    ย้อนไป 3 รอบเพราะวันจ่ายของรอบก่อนหน้ายังไม่ถึงตอนต้นรอบใหม่ เช่นวันที่
    27 ก.ย. วันจ่ายที่ผ่านมาแล้วจริงๆ คือ 28 ส.ค. ซึ่งเป็นของรอบเมื่อ 2 รอบก่อน
    """
    current = period_containing(today)
    prev = previous_period(current)
    prev2 = previous_period(prev)
    periods = [prev2, prev, current]

    cutoff_at = settings.payroll_cutoff_notice_at
    cycle_at = settings.payroll_cycle_notice_at

    return {
        NOTICE_CUTOFF: [(datetime.combine(p.end, cutoff_at), p) for p in periods],
        NOTICE_CYCLE_START: [(datetime.combine(p.start, cycle_at), p) for p in periods],
        NOTICE_PAYDAY: [(datetime.combine(p.payday, cycle_at), p) for p in periods],
    }


def due_notices(now: datetime | None = None) -> list[tuple[str, PayrollPeriod, datetime]]:
    """ข้อความที่ถึงกำหนดส่งแล้วและยังไม่เกินหน้าต่างตามหลัง

    คืน (ชนิด, รอบ, เวลาที่ควรส่ง) — ผู้เรียกยังต้องเช็คต่อว่าส่งไปแล้วหรือยัง
    """
    now = now or local_now()
    catchup = timedelta(hours=settings.payroll_notice_catchup_hours)
    result = []

    for kind, moments in _scheduled_moments(now.date()).items():
        past = [(moment, period) for moment, period in moments if moment <= now]
        if not past:
            continue
        moment, period = max(past, key=lambda item: item[0])
        if now - moment <= catchup:
            result.append((kind, period, moment))

    return result


def already_sent(db: Session, employee_id: int, period: PayrollPeriod, kind: str) -> bool:
    return (
        db.query(PayrollNotice)
        .filter(
            PayrollNotice.employee_id == employee_id,
            PayrollNotice.period_key == period.key,
            PayrollNotice.kind == kind,
            PayrollNotice.ok.is_(True),
        )
        .first()
        is not None
    )


# ---------------------------------------------------------------------------
# สร้างข้อความ + ส่ง
# ---------------------------------------------------------------------------


def build_message(
    db: Session, employee: Employee, kind: str, period: PayrollPeriod
) -> tuple[dict, str, PayrollSummary]:
    """คืน (การ์ด Flex, ข้อความสำรอง, สรุปที่ใช้สร้าง)"""
    if kind == NOTICE_CYCLE_START:
        # รอบเพิ่งเริ่ม ยังไม่มีการลงเวลา — ข้อความจึงเป็น "เป้าหมาย" ไม่ใช่ผลจริง
        summary = summary_for(db, employee, period, as_of=period.start)
        projected = projected_full_period(
            period, salary_of(employee), employee.start_date
        )
        return (
            cycle_start_bubble(summary, projected),
            alt_text(kind, summary),
            summary,
        )

    summary = summary_for(db, employee, period, as_of=period.end)
    bubble = cutoff_bubble(summary) if kind == NOTICE_CUTOFF else payday_bubble(summary)
    return bubble, alt_text(kind, summary), summary


def send_notice(
    db: Session,
    employee: Employee,
    kind: str,
    period: PayrollPeriod,
    *,
    force: bool = False,
    dry_run: bool = False,
) -> dict:
    """ส่งข้อความหนึ่งใบให้พนักงานหนึ่งคน — ไม่เคย raise

    เหมือน notify_line: ปัญหาเรื่อง LINE ต้องไม่ทำให้ทั้งรอบล้ม พนักงานคนอื่น
    ต้องยังได้รับข้อความของตัวเอง
    """
    if kind not in NOTICE_KINDS:
        return {"employee": employee.employee_code, "kind": kind, "sent": False,
                "reason": f"ไม่รู้จักชนิดข้อความ '{kind}'"}

    result = {
        "employee_id": employee.id,
        "employee": employee.employee_code,
        "name": (employee.full_name or "").strip() or employee.employee_code,
        "kind": kind,
        "period": period.key,
        "sent": False,
    }

    if not force and already_sent(db, employee.id, period, kind):
        result["reason"] = "ส่งไปแล้วในรอบนี้"
        return result

    try:
        bubble, alt, summary = build_message(db, employee, kind, period)
    except Exception as e:
        log.warning("สร้างข้อความเงินเดือนไม่สำเร็จ (%s): %s", employee.employee_code, e)
        result["reason"] = f"สร้างข้อความไม่สำเร็จ: {e}"
        return result

    result["amount"] = summary.net
    result["text"] = summary_text(kind, summary)

    if dry_run:
        result["reason"] = "dry-run — ไม่ได้ส่งจริง"
        return result

    if not is_configured():
        result["reason"] = "ยังไม่ได้ตั้งค่า LINE"
        return result

    ok = push_flex(alt, bubble, to=settings.payroll_target_id)
    result["sent"] = ok
    if not ok:
        result["reason"] = "LINE ตีกลับ — ดู log ของ backend"

    # บันทึกทั้งกรณีสำเร็จและไม่สำเร็จ: แถวที่ ok=False ทำให้รอบถัดไปลองส่งใหม่ได้
    # เพราะ already_sent() นับเฉพาะแถวที่ ok=True
    db.add(
        PayrollNotice(
            employee_id=employee.id,
            period_key=period.key,
            kind=kind,
            ok=ok,
            amount=summary.net,
        )
    )
    db.commit()
    return result


def run_due(
    db: Session,
    *,
    now: datetime | None = None,
    force: bool = False,
    dry_run: bool = False,
    only_kind: str | None = None,
) -> dict:
    """ตัวหลักที่ Scheduled Task เรียก — ส่งทุกข้อความที่ถึงกำหนดแล้ว"""
    now = now or local_now()
    report = {
        "now": now.isoformat(timespec="minutes"),
        "enabled": settings.payroll_enabled,
        "line_ready": is_configured(),
        "due": [],
        "results": [],
    }

    if not settings.payroll_enabled:
        report["reason"] = "ปิดไว้ที่ PAYROLL_ENABLED=false"
        return report

    employees = payroll_employees(db)
    if not employees:
        report["reason"] = (
            "ไม่มีพนักงานที่ตั้งเงินเดือนไว้ — ตั้ง employees.base_salary "
            "หรือ PAYROLL_DEFAULT_SALARY ใน .env"
        )
        return report

    for kind, period, moment in due_notices(now):
        if only_kind and kind != only_kind:
            continue
        report["due"].append(
            {"kind": kind, "period": period.key, "scheduled_at": moment.isoformat(timespec="minutes")}
        )
        for employee in employees:
            report["results"].append(
                send_notice(db, employee, kind, period, force=force, dry_run=dry_run)
            )

    return report


def status(db: Session, now: datetime | None = None) -> dict:
    """ภาพรวมให้ /payroll/status และ CLI --status ใช้ร่วมกัน"""
    now = now or local_now()
    today = now.date()
    current = period_containing(today)
    upcoming = next_period(current)

    return {
        "enabled": settings.payroll_enabled,
        "line_ready": is_configured(),
        "target_configured": bool(settings.payroll_target_id),
        "separate_payroll_target": bool(settings.payroll_line_target_id.strip()),
        "now": now.isoformat(timespec="minutes"),
        "cutoff_day": settings.payroll_cutoff_day,
        "payday": settings.payroll_payday,
        "prorate_basis": settings.payroll_prorate_basis,
        "current_period": {
            "start": current.start.isoformat(),
            "end": current.end.isoformat(),
            "payday": current.payday.isoformat(),
            "label": current.label,
            "days_until_cutoff": (current.end - today).days,
            "days_until_payday": (current.payday - today).days,
        },
        "next_period": {
            "start": upcoming.start.isoformat(),
            "end": upcoming.end.isoformat(),
            "payday": upcoming.payday.isoformat(),
        },
        "due_now": [
            {"kind": kind, "period": period.key}
            for kind, period, _ in due_notices(now)
        ],
        "employees_in_payroll": [
            {
                "employee_id": emp.id,
                "employee_code": emp.employee_code,
                "name": (emp.full_name or "").strip() or emp.employee_code,
                "base_salary": salary_of(emp),
                "start_date": emp.start_date.isoformat() if emp.start_date else None,
            }
            for emp in payroll_employees(db)
        ],
    }
