"""Endpoint ฝั่งเงินเดือน — ดูยอดสะสม ตั้งเงินเดือน และสั่งส่งแจ้งเตือน

กติกาเรื่องสิทธิ์ในไฟล์นี้: **เงินเดือนเป็นข้อมูลส่วนตัว**
    - พนักงานทั่วไปดูได้เฉพาะของตัวเอง
    - หัวหน้าดูของคนอื่นได้ และเป็นคนเดียวที่ตั้งเงินเดือน/สั่งส่งได้
    - `/payroll/status` มีเงินเดือนของทุกคนอยู่ จึงเป็นของหัวหน้าเท่านั้น
"""

from datetime import date

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Employee
from ..payroll import (
    PayrollSummary,
    next_period,
    period_containing,
    period_in_focus,
    period_paid_on,
    previous_period,
)
from ..payroll_models import NOTICE_KINDS
from ..payroll_service import (
    local_now,
    run_due,
    salary_of,
    send_notice,
    status as payroll_status,
    summary_for,
)
from ..security import get_current_employee, require_manager

router = APIRouter(prefix="/payroll", tags=["payroll"])


def _summary_dict(summary: PayrollSummary) -> dict:
    return {
        "employee_name": summary.employee_name,
        "period": {
            "start": summary.period.start.isoformat(),
            "end": summary.period.end.isoformat(),
            "payday": summary.period.payday.isoformat(),
            "label": summary.period.label,
            "key": summary.period.key,
        },
        "base_salary": summary.base_salary,
        "employment_start": (
            summary.employment_start.isoformat() if summary.employment_start else None
        ),
        "counted_from": summary.counted_from.isoformat(),
        "as_of": summary.as_of.isoformat(),
        "period_closed": summary.period_closed,
        "days": {
            "work_days_total": summary.work_days_total,
            "work_days_elapsed": summary.work_days_elapsed,
            "remaining": summary.remaining_work_days,
            "present": summary.present_days,
            "absent": summary.absent_days,
            "late": summary.late_days,
            "late_minutes": summary.late_minutes,
        },
        "money": {
            "daily_rate": summary.daily_rate,
            "gross": summary.gross,
            "deduction_absent": summary.deduction_absent,
            "deduction_late": summary.deduction_late,
            "social_security": summary.social_security,
            "net": summary.net,
        },
        "basis": summary.basis,
        "notes": summary.notes,
    }


def _resolve_employee(
    db: Session, viewer: Employee, employee_id: int | None
) -> Employee:
    """พนักงานที่จะดูยอด — คนอื่นได้เฉพาะหัวหน้า"""
    if employee_id is None or employee_id == viewer.id:
        return viewer
    if not viewer.is_manager:
        raise HTTPException(status_code=403, detail="ดูยอดเงินของคนอื่นไม่ได้")
    target = db.query(Employee).filter(Employee.id == employee_id).first()
    if target is None:
        raise HTTPException(status_code=404, detail="ไม่พบพนักงาน")
    return target


@router.get("/summary")
def summary(
    employee_id: int | None = Query(None, description="ไม่ส่ง = ของตัวเอง (หัวหน้าเท่านั้นที่ดูของคนอื่นได้)"),
    which: str = Query(
        "current",
        pattern="^(current|previous|next|paid_today)$",
        description="current = รอบที่กำลังเดิน, previous = รอบก่อน, next = รอบหน้า, paid_today = รอบที่เงินออกวันนี้",
    ),
    viewer: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ยอดสะสมของรอบ — เปิดดูได้ตลอด ไม่ต้องรอวันตัดรอบ

    นี่คือ endpoint ที่เว็บ/แอปเอาไปทำการ์ด "รอบนี้ได้เท่าไรแล้ว"
    """
    employee = _resolve_employee(db, viewer, employee_id)
    if salary_of(employee) <= 0:
        raise HTTPException(
            status_code=409,
            detail="ยังไม่ได้ตั้งเงินเดือนของพนักงานคนนี้ "
            "(ตั้งที่ PUT /payroll/employees/{id}/salary หรือ PAYROLL_DEFAULT_SALARY)",
        )

    today = local_now().date()
    current = period_containing(today)
    period = {
        "current": current,
        "previous": previous_period(current),
        "next": next_period(current),
        "paid_today": period_paid_on(today),
    }[which]

    as_of = min(today, period.end)
    return _summary_dict(summary_for(db, employee, period, as_of=as_of))


@router.get("/status")
def status(
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """สถานะระบบเงินเดือน + รอบปัจจุบัน + ใครอยู่ในระบบบ้าง (หัวหน้าเท่านั้น)"""
    return payroll_status(db)


@router.put("/employees/{employee_id}/salary")
def set_salary(
    employee_id: int,
    base_salary: float = Body(..., embed=True, ge=0, description="บาท/เดือน — 0 = เอาออกจากระบบเงินเดือน"),
    start_date: date | None = Body(None, embed=True, description="วันเริ่มงาน ใช้เฉลี่ยเงินรอบแรก"),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """ตั้งเงินเดือนและวันเริ่มงาน (หัวหน้าเท่านั้น)

    วันเริ่มงานสำคัญกับ "รอบแรก" — เข้างานกลางรอบแล้วได้เงินไม่เต็มเดือน
    ถ้าไม่ตั้ง ระบบจะถือว่าทำงานมาตั้งแต่ต้นรอบและคิดเต็มเดือนให้
    """
    employee = db.query(Employee).filter(Employee.id == employee_id).first()
    if employee is None:
        raise HTTPException(status_code=404, detail="ไม่พบพนักงาน")

    employee.base_salary = base_salary or None
    if start_date is not None:
        employee.start_date = start_date
    db.commit()
    db.refresh(employee)

    return {
        "employee_id": employee.id,
        "employee_code": employee.employee_code,
        "base_salary": employee.base_salary,
        "start_date": employee.start_date.isoformat() if employee.start_date else None,
        "in_payroll": salary_of(employee) > 0,
    }


@router.post("/notify")
def notify(
    kind: str = Query(..., description="cutoff | cycle_start | payday"),
    employee_id: int | None = Query(None, description="ไม่ส่ง = ส่งให้ทุกคนในระบบเงินเดือน"),
    which: str = Query(
        "auto",
        pattern="^(auto|current|previous)$",
        description="auto = เลือกรอบที่ตรงกับชนิดข้อความให้เอง",
    ),
    force: bool = Query(False, description="ส่งซ้ำแม้รอบนี้เคยส่งไปแล้ว"),
    dry_run: bool = Query(False, description="สร้างข้อความให้ดูแต่ไม่ส่งจริง"),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """สั่งส่งข้อความทันที (หัวหน้าเท่านั้น) — ใช้ทดสอบหน้าตาการ์ดก่อนถึงวันจริง

    `dry_run=true` คืนข้อความที่จะส่งโดยไม่ยิงเข้า LINE และไม่บันทึกว่าส่งแล้ว
    """
    if kind not in NOTICE_KINDS:
        raise HTTPException(
            status_code=400, detail=f"kind ต้องเป็นหนึ่งใน {', '.join(NOTICE_KINDS)}"
        )

    today = local_now().date()
    current = period_containing(today)
    if which == "current":
        period = current
    elif which == "previous":
        period = previous_period(current)
    else:
        # cycle_start พูดถึงรอบที่กำลังเดิน ส่วน cutoff/payday พูดถึงรอบที่เงินกำลังจะออก
        # ซึ่งวันที่ 27-28 ไม่ใช่รอบเดียวกับรอบที่วันนี้อยู่ (ดู period_in_focus)
        period = current if kind == "cycle_start" else period_in_focus(today)

    from ..payroll_service import payroll_employees

    if employee_id is not None:
        target = db.query(Employee).filter(Employee.id == employee_id).first()
        if target is None:
            raise HTTPException(status_code=404, detail="ไม่พบพนักงาน")
        employees = [target]
    else:
        employees = payroll_employees(db)

    if not employees:
        raise HTTPException(
            status_code=409,
            detail="ไม่มีพนักงานที่ตั้งเงินเดือนไว้ — ตั้งก่อนที่ PUT /payroll/employees/{id}/salary",
        )

    return {
        "kind": kind,
        "period": period.key,
        "results": [
            send_notice(db, emp, kind, period, force=force, dry_run=dry_run)
            for emp in employees
        ],
    }


@router.post("/run-due")
def run_due_now(
    force: bool = Query(False),
    dry_run: bool = Query(False),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """ส่งทุกข้อความที่ถึงกำหนดแล้วและยังไม่ได้ส่ง

    เป็นตัวเดียวกับที่ Scheduled Task เรียกผ่าน `send_payroll_notice.py`
    มีไว้ให้กดจากเว็บ/แอปได้ด้วยเวลาสงสัยว่าตกรอบไปหรือเปล่า
    """
    return run_due(db, force=force, dry_run=dry_run)
