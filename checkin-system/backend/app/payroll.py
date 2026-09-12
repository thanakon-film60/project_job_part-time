"""คำนวณรอบเงินเดือนและประมาณการรายได้

รอบของบริษัทนี้ไม่ตรงกับเดือนปฏิทิน:

    วันที่ 26  = วันตัดรอบ (วันสุดท้ายที่นับเข้ารอบนี้)
    วันที่ 27  = วันแรกของรอบถัดไป
    วันที่ 28  = วันจ่ายเงินของรอบที่เพิ่งตัดไป

    รอบหนึ่ง = 27 ของเดือนก่อน  ..  26 ของเดือนนี้   แล้วจ่าย 28 ของเดือนนี้

ระวังจุดที่คนอ่านโค้ดมักพลาด: **วันที่ 28 ไม่ได้อยู่ในรอบที่กำลังจ่าย**
วันที่ 28 อยู่ในรอบใหม่ (ที่เริ่มไปแล้วเมื่อวันที่ 27) แต่เงินที่จ่ายเป็นของรอบเก่า
ฟังก์ชันจึงแยกเป็น `period_containing()` (วันนี้อยู่รอบไหน) กับ
`period_paid_on()` (เงินที่จ่ายวันนี้เป็นของรอบไหน) อย่าเอามาใช้สลับกัน

โมดูลนี้ **ไม่แตะฐานข้อมูลและไม่รู้จัก SQLAlchemy** — รับ date/set เข้ามาแล้ว
คืนตัวเลขอย่างเดียว เหมือน work_schedule.py จึงเขียนเทสต์ได้โดยไม่ต้องมี DB
"""

from calendar import monthrange
from dataclasses import dataclass, field
from datetime import date, timedelta

from .config import settings

# ---------------------------------------------------------------------------
# ปฏิทินพื้นฐาน
# ---------------------------------------------------------------------------

THAI_MONTHS_SHORT = [
    "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
]


def thai_date(value: date) -> str:
    """2026-09-26 -> "26 ก.ย. 2026" (ใช้ ค.ศ. ให้ตรงกับส่วนอื่นของระบบ)"""
    return f"{value.day} {THAI_MONTHS_SHORT[value.month]} {value.year}"


def baht(amount: float) -> str:
    """7800.0 -> "7,800" / 6840.5 -> "6,840.50" — ตัดทศนิยม .00 ทิ้งให้อ่านง่าย"""
    rounded = round(float(amount) + 0.0, 2)
    if abs(rounded - round(rounded)) < 0.005:
        return f"{int(round(rounded)):,}"
    return f"{rounded:,.2f}"


def _clamp_day(year: int, month: int, day: int) -> date:
    """วันที่ที่ไม่มีจริงให้ถอยไปวันสุดท้ายของเดือน (เช่น 31 ก.พ. -> 28/29 ก.พ.)

    วันที่ 26/27/28 มีครบทุกเดือนอยู่แล้ว ฟังก์ชันนี้จึงเป็นแค่กันเหนียว
    เผื่อมีคนตั้ง PAYROLL_CUTOFF_DAY=31 ใน .env
    """
    last = monthrange(year, month)[1]
    return date(year, month, min(max(day, 1), last))


def _shift_month(year: int, month: int, delta: int) -> tuple[int, int]:
    index = (year * 12 + (month - 1)) + delta
    return index // 12, index % 12 + 1


def daterange(start: date, end: date):
    """ไล่วันตั้งแต่ start ถึง end แบบรวมปลายทั้งสองข้าง"""
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


# ---------------------------------------------------------------------------
# รอบเงินเดือน
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PayrollPeriod:
    """รอบจ่ายเงินหนึ่งรอบ (ปลายทั้งสองข้างรวมอยู่ในรอบ)"""

    start: date
    end: date       # = วันตัดรอบ
    payday: date

    @property
    def key(self) -> str:
        """คีย์ประจำรอบ ใช้กันส่งแจ้งเตือนซ้ำ — ผูกกับวันจ่ายเพราะไม่ซ้ำแน่นอน"""
        return self.payday.isoformat()

    @property
    def label(self) -> str:
        return f"{thai_date(self.start)} – {thai_date(self.end)}"

    @property
    def total_days(self) -> int:
        return (self.end - self.start).days + 1

    def contains(self, day: date) -> bool:
        return self.start <= day <= self.end


def _period_from_end(end: date) -> PayrollPeriod:
    cutoff_day = settings.payroll_cutoff_day
    payday_day = settings.payroll_payday

    prev_year, prev_month = _shift_month(end.year, end.month, -1)
    start = _clamp_day(prev_year, prev_month, cutoff_day) + timedelta(days=1)

    # จ่ายหลังวันตัดรอบในเดือนเดียวกัน (26 -> 28) แต่ถ้าตั้งวันจ่ายไว้ก่อน
    # หรือเท่ากับวันตัดรอบ แปลว่าตั้งใจให้ไปจ่ายเดือนถัดไป (26 -> 5 ของเดือนหน้า)
    if payday_day > cutoff_day:
        payday = _clamp_day(end.year, end.month, payday_day)
    else:
        pay_year, pay_month = _shift_month(end.year, end.month, 1)
        payday = _clamp_day(pay_year, pay_month, payday_day)

    return PayrollPeriod(start=start, end=end, payday=payday)


def period_containing(day: date) -> PayrollPeriod:
    """รอบที่ "วันนี้" อยู่ — ใช้ตอนดูยอดสะสมระหว่างรอบ"""
    cutoff_this = _clamp_day(day.year, day.month, settings.payroll_cutoff_day)
    if day <= cutoff_this:
        return _period_from_end(cutoff_this)
    next_year, next_month = _shift_month(day.year, day.month, 1)
    return _period_from_end(_clamp_day(next_year, next_month, settings.payroll_cutoff_day))


def period_paid_on(day: date) -> PayrollPeriod:
    """รอบที่ "เงินที่จ่ายวันนี้" เป็นของรอบนั้น

    วันที่ 28 ก.ย. อยู่ในรอบใหม่ (27 ก.ย.–26 ต.ค.) แต่เงินที่ออกเป็นของ
    รอบเก่า (27 ส.ค.–26 ก.ย.) ฟังก์ชันนี้คืนรอบเก่า

    ถ้าวันที่ส่งมาไม่ใช่วันจ่ายเงิน จะคืน **รอบที่จ่ายไปแล้วล่าสุด** ซึ่งอาจ
    ต้องถอยหลังสองรอบ เช่นวันที่ 27 ก.ย. รอบก่อนหน้ายังไม่ได้จ่าย (จ่าย 28 ก.ย.)
    รอบที่จ่ายไปแล้วจริงๆ คือรอบที่จ่ายเมื่อ 28 ส.ค.
    """
    period = period_containing(day)
    if period.payday == day:
        return period
    period = previous_period(period)
    # ถอยจนกว่าจะเจอรอบที่ถึงวันจ่ายแล้วจริง (ปกติวนไม่เกิน 1 รอบ)
    while period.payday > day:
        period = previous_period(period)
    return period


def previous_period(period: PayrollPeriod) -> PayrollPeriod:
    return _period_from_end(period.start - timedelta(days=1))


def period_in_focus(day: date) -> PayrollPeriod:
    """รอบที่ "กำลังพูดถึงเรื่องเงิน" ณ วันนี้ = รอบที่วันจ่ายใกล้ที่สุดข้างหน้า

    ใช้ตอนสั่งส่งข้อความเองเพื่อดูหน้าตาการ์ด ซึ่งต่างจาก `period_containing`:

        11 ก.ย. -> 27 ส.ค.–26 ก.ย. (จ่าย 28 ก.ย.)  = รอบที่วันนี้อยู่
        27 ก.ย. -> 27 ส.ค.–26 ก.ย. (จ่าย 28 ก.ย.)  = รอบที่เพิ่งตัด ไม่ใช่รอบใหม่ที่เริ่มวันนี้
        29 ก.ย. -> 27 ก.ย.–26 ต.ค. (จ่าย 28 ต.ค.)  = จ่ายรอบเก่าไปแล้ว ขยับมารอบใหม่

    ถ้าใช้ `period_containing` ตรงๆ วันที่ 27-28 จะได้รอบใหม่ที่ยังไม่มีข้อมูล
    แทนที่จะเป็นรอบที่เงินกำลังจะออก
    """
    current = period_containing(day)
    prev = previous_period(current)
    return prev if prev.payday >= day else current


def next_period(period: PayrollPeriod) -> PayrollPeriod:
    year, month = _shift_month(period.end.year, period.end.month, 1)
    return _period_from_end(_clamp_day(year, month, settings.payroll_cutoff_day))


# ---------------------------------------------------------------------------
# วันทำงาน
# ---------------------------------------------------------------------------


def work_days_in(
    start: date,
    end: date,
    *,
    work_weekdays: set[int] | None = None,
    holidays: set[date] | None = None,
) -> list[date]:
    """วันที่ "ต้องมาทำงาน" ในช่วงที่กำหนด

    วันหยุดประจำสัปดาห์และวันหยุดนักขัตฤกษ์ถูกตัดออก **โดยตั้งใจ** เพราะ
    วันหยุดเป็นวันที่ได้เงินอยู่แล้วตามเงินเดือน การไม่มาในวันหยุดจึงต้องไม่
    ถูกนับเป็นขาดงาน (ไม่งั้นเสาร์อาทิตย์จะโดนหักเงินทุกสัปดาห์)
    """
    if end < start:
        return []
    weekdays = work_weekdays if work_weekdays is not None else settings.payroll_weekdays_set
    off = holidays if holidays is not None else settings.payroll_holidays_set
    return [
        day
        for day in daterange(start, end)
        if day.isoweekday() in weekdays and day not in off
    ]


# ---------------------------------------------------------------------------
# ประมาณการรายได้
# ---------------------------------------------------------------------------


@dataclass
class PayrollSummary:
    """สรุปเงินของพนักงานหนึ่งคนในรอบหนึ่งรอบ"""

    period: PayrollPeriod
    employee_name: str
    base_salary: float
    employment_start: date | None

    # ขอบเขตที่นับ
    counted_from: date          # วันแรกของรอบที่นับให้คนนี้ (เริ่มงานกลางรอบ = วันเริ่มงาน)
    as_of: date                 # นับถึงวันไหน (ตอนตัดรอบ = วันตัดรอบ)
    period_closed: bool         # ผ่านวันตัดรอบแล้วหรือยัง

    # จำนวนวัน
    work_days_total: int        # วันทำงานทั้งรอบของคนนี้ (ถึงวันตัดรอบ)
    work_days_elapsed: int      # วันทำงานที่ผ่านมาแล้ว (ถึง as_of)
    present_days: int
    absent_days: int
    late_days: int
    late_minutes: int

    # เงิน
    daily_rate: float
    gross: float                # รายได้ของรอบนี้ก่อนหักอะไรเลย
    deduction_absent: float
    deduction_late: float
    social_security: float
    net: float

    basis: str                  # calendar_30 | work_days
    notes: list[str] = field(default_factory=list)

    @property
    def remaining_work_days(self) -> int:
        return max(self.work_days_total - self.work_days_elapsed, 0)

    @property
    def attendance_text(self) -> str:
        return f"{self.present_days}/{self.work_days_elapsed} วัน"


def _social_security(gross: float) -> float:
    """ประกันสังคม ม.33 — 5% ของค่าจ้าง ฐาน 1,650–15,000 บาท (สูงสุด 750)

    ฐานถูกตรึงไว้ที่ 15,000 ตามกฎหมาย เงินเดือน 18,000 จึงหัก 750 ไม่ใช่ 900
    """
    if not settings.payroll_social_security_enabled or gross <= 0:
        return 0.0
    floor = settings.payroll_social_security_floor
    ceiling = settings.payroll_social_security_ceiling
    base = min(max(gross, floor), ceiling)
    return round(base * settings.payroll_social_security_rate, 2)


def build_summary(
    *,
    period: PayrollPeriod,
    employee_name: str,
    base_salary: float,
    employment_start: date | None = None,
    present_days: set[date] | None = None,
    late_days: set[date] | None = None,
    late_minutes: int = 0,
    as_of: date | None = None,
) -> PayrollSummary:
    """คำนวณยอดของพนักงานหนึ่งคนในรอบหนึ่งรอบ

    [present_days] / [late_days] = วัน (เวลาไทย) ที่มีการลงเวลาเข้างานจริง
    ผู้เรียกเป็นคนดึงจากฐานข้อมูลมาให้ โมดูลนี้ไม่ query เอง
    """
    present = set(present_days or ())
    late = set(late_days or ())
    as_of = as_of or period.end
    # นับเกินวันตัดรอบไม่ได้ — รอบปิดแล้วก็คือปิดแล้ว
    as_of = min(as_of, period.end)

    counted_from = period.start
    notes: list[str] = []
    if employment_start and employment_start > period.start:
        counted_from = employment_start
        notes.append(
            f"รอบนี้เริ่มนับตั้งแต่วันเริ่มงาน {thai_date(employment_start)} "
            f"ไม่ใช่ทั้งรอบ จึงได้ไม่เต็มเดือน"
        )

    # เริ่มงานหลังวันตัดรอบ = รอบนี้ยังไม่มีสิทธิ์อะไรเลย
    if counted_from > period.end:
        return PayrollSummary(
            period=period,
            employee_name=employee_name,
            base_salary=base_salary,
            employment_start=employment_start,
            counted_from=counted_from,
            as_of=as_of,
            period_closed=as_of >= period.end,
            work_days_total=0,
            work_days_elapsed=0,
            present_days=0,
            absent_days=0,
            late_days=0,
            late_minutes=0,
            daily_rate=0.0,
            gross=0.0,
            deduction_absent=0.0,
            deduction_late=0.0,
            social_security=0.0,
            net=0.0,
            basis=settings.payroll_prorate_basis,
            notes=[f"ยังไม่เริ่มงานในรอบนี้ (เริ่ม {thai_date(employment_start)})"]
            if employment_start
            else ["ยังไม่เริ่มงานในรอบนี้"],
        )

    days_total = work_days_in(counted_from, period.end)
    days_elapsed = work_days_in(counted_from, as_of)
    full_period_days = work_days_in(period.start, period.end)

    present_in_range = {day for day in present if counted_from <= day <= as_of}
    late_in_range = {day for day in late if counted_from <= day <= as_of}

    elapsed_set = set(days_elapsed)
    # มาทำงานนอกวันทำงาน (เช่นเสาร์) ไม่ถูกนับเป็นขาดงานติดลบ แค่ไม่หักเพิ่ม
    present_on_workdays = present_in_range & elapsed_set
    absent = len(elapsed_set - present_in_range)

    basis = settings.payroll_prorate_basis
    if basis == "work_days" and full_period_days:
        daily_rate = base_salary / len(full_period_days)
        gross = daily_rate * len(days_total)
    else:
        basis = "calendar_30"
        divisor = settings.payroll_calendar_divisor or 30
        daily_rate = base_salary / divisor
        if counted_from <= period.start:
            gross = float(base_salary)
        else:
            calendar_days = (period.end - counted_from).days + 1
            gross = daily_rate * calendar_days

    deduction_absent = round(daily_rate * absent, 2)
    deduction_late = 0.0
    if settings.payroll_late_deduction_per_day > 0:
        deduction_late = round(
            settings.payroll_late_deduction_per_day * len(late_in_range), 2
        )

    gross = round(gross, 2)
    payable = max(gross - deduction_absent - deduction_late, 0.0)
    sso = _social_security(payable)
    net = round(max(payable - sso, 0.0), 2)

    if absent:
        notes.append(f"ขาดงาน {absent} วัน หักวันละ {baht(daily_rate)} บาท")
    if len(late_in_range) and not deduction_late:
        notes.append(
            f"มาสาย {len(late_in_range)} วัน — ตั้งค่าไว้ไม่หักเงิน "
            f"(เปิดได้ที่ PAYROLL_LATE_DEDUCTION_PER_DAY)"
        )

    return PayrollSummary(
        period=period,
        employee_name=employee_name,
        base_salary=float(base_salary),
        employment_start=employment_start,
        counted_from=counted_from,
        as_of=as_of,
        period_closed=as_of >= period.end,
        work_days_total=len(days_total),
        work_days_elapsed=len(days_elapsed),
        present_days=len(present_on_workdays),
        absent_days=absent,
        late_days=len(late_in_range),
        late_minutes=late_minutes,
        daily_rate=round(daily_rate, 2),
        gross=gross,
        deduction_absent=deduction_absent,
        deduction_late=deduction_late,
        social_security=sso,
        net=net,
        basis=basis,
        notes=notes,
    )


def projected_full_period(period: PayrollPeriod, base_salary: float,
                          employment_start: date | None = None) -> PayrollSummary:
    """ยอดที่จะได้ "ถ้ามาครบทุกวัน" — ใช้ในข้อความวันเริ่มรอบใหม่"""
    days = work_days_in(
        max(period.start, employment_start or period.start), period.end
    )
    return build_summary(
        period=period,
        employee_name="",
        base_salary=base_salary,
        employment_start=employment_start,
        present_days=set(days),
        as_of=period.end,
    )
