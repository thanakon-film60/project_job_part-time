"""python -m unittest test_payroll -v -- ไม่แตะ DB จริงและไม่ยิง LINE จริง

ครอบคลุม 3 เรื่องที่พังแล้วเจ็บที่สุด:
  1. ขอบรอบ 26/27/28 โดยเฉพาะวันที่ 28 ที่ "อยู่รอบใหม่แต่จ่ายเงินรอบเก่า"
  2. การเฉลี่ยเงินตอนเข้างานกลางรอบ (เงินรอบแรกของคนเพิ่งเริ่มงาน)
  3. การกันส่งซ้ำ — Scheduled Task ยิงวันละ 2 รอบ ห้ามได้ข้อความซ้ำ
"""

import unittest
from contextlib import contextmanager
from datetime import date, datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import payroll, payroll_service
from app.config import settings
from app.line_flex import alt_text, cutoff_bubble, cycle_start_bubble, payday_bubble
from app.models import CheckIn, Employee
from app.payroll import (
    build_summary,
    next_period,
    period_containing,
    period_paid_on,
    previous_period,
    projected_full_period,
    work_days_in,
)
from app.payroll_models import (
    NOTICE_CUTOFF,
    NOTICE_CYCLE_START,
    NOTICE_PAYDAY,
    PayrollNotice,
)

SEP = lambda day: date(2026, 9, day)  # noqa: E731 — ย่อให้เทสต์อ่านง่าย


@contextmanager
def override(**values):
    """เปลี่ยนค่า settings ชั่วคราวแล้วคืนค่าเดิมเสมอ"""
    previous = {key: getattr(settings, key) for key in values}
    for key, value in values.items():
        setattr(settings, key, value)
    try:
        yield
    finally:
        for key, value in previous.items():
            setattr(settings, key, value)


class PeriodBoundaryTests(unittest.TestCase):
    """รอบ 27 ของเดือนก่อน -> 26 ของเดือนนี้ จ่าย 28"""

    def test_day_before_cutoff_is_in_closing_period(self):
        period = period_containing(SEP(11))
        self.assertEqual(period.start, date(2026, 8, 27))
        self.assertEqual(period.end, SEP(26))
        self.assertEqual(period.payday, SEP(28))

    def test_cutoff_day_itself_is_the_last_day_of_the_period(self):
        self.assertEqual(period_containing(SEP(26)).end, SEP(26))

    def test_day_27_starts_the_next_period(self):
        period = period_containing(SEP(27))
        self.assertEqual(period.start, SEP(27))
        self.assertEqual(period.end, date(2026, 10, 26))
        self.assertEqual(period.payday, date(2026, 10, 28))

    def test_payday_belongs_to_the_new_period_but_pays_the_old_one(self):
        """จุดที่คนอ่านโค้ดพลาดบ่อยที่สุด"""
        self.assertEqual(period_containing(SEP(28)).start, SEP(27))
        paid = period_paid_on(SEP(28))
        self.assertEqual(paid.start, date(2026, 8, 27))
        self.assertEqual(paid.end, SEP(26))

    def test_period_paid_on_non_payday_returns_last_actually_paid_period(self):
        # 27 ก.ย. รอบก่อนหน้ายังไม่จ่าย (จ่าย 28 ก.ย.) ต้องถอยไปรอบที่จ่าย 28 ส.ค.
        paid = period_paid_on(SEP(27))
        self.assertEqual(paid.payday, date(2026, 8, 28))
        self.assertLessEqual(paid.payday, SEP(27))

    def test_period_in_focus_follows_the_money_not_the_calendar(self):
        """รอบที่ "กำลังพูดถึงเรื่องเงิน" ต่างจากรอบที่วันนี้อยู่ในวันที่ 27-28"""
        # ระหว่างรอบ: รอบที่วันนี้อยู่ = รอบที่เงินกำลังจะออก
        self.assertEqual(payroll.period_in_focus(SEP(11)).payday, SEP(28))
        self.assertEqual(payroll.period_in_focus(SEP(26)).payday, SEP(28))
        # วันเริ่มรอบใหม่และวันเงินออก: ยังต้องเป็นรอบเก่าที่เงินกำลังจะออก
        self.assertEqual(payroll.period_in_focus(SEP(27)).end, SEP(26))
        self.assertEqual(payroll.period_in_focus(SEP(28)).end, SEP(26))
        # จ่ายไปแล้ว ขยับมารอบใหม่
        self.assertEqual(payroll.period_in_focus(SEP(29)).payday, date(2026, 10, 28))

    def test_period_in_focus_differs_from_period_containing_on_payday(self):
        self.assertNotEqual(
            payroll.period_in_focus(SEP(28)).key, period_containing(SEP(28)).key
        )

    def test_previous_and_next_are_inverses(self):
        period = period_containing(SEP(11))
        self.assertEqual(previous_period(next_period(period)), period)

    def test_period_key_is_the_payday(self):
        self.assertEqual(period_containing(SEP(11)).key, "2026-09-28")

    def test_cutoff_day_clamps_to_short_months(self):
        """ตั้ง 31 แล้วเจอเดือน ก.พ. ต้องถอยไปวันสุดท้ายของเดือน ไม่ใช่ล่ม"""
        with override(payroll_cutoff_day=31, payroll_payday=5):
            period = period_containing(date(2026, 2, 10))
            self.assertEqual(period.end, date(2026, 2, 28))
            # วันจ่าย (5) มาก่อนวันตัดรอบ (31) = ตั้งใจให้ไปจ่ายเดือนถัดไป
            self.assertEqual(period.payday, date(2026, 3, 5))


class WorkDayTests(unittest.TestCase):
    def test_weekends_are_not_work_days(self):
        days = work_days_in(SEP(14), SEP(26))
        self.assertEqual(len(days), 10)
        self.assertTrue(all(day.isoweekday() <= 5 for day in days))

    def test_holidays_are_removed_not_counted_as_absence(self):
        with override(payroll_holidays="2026-09-15,2026-09-16"):
            self.assertEqual(len(work_days_in(SEP(14), SEP(26))), 8)

    def test_broken_holiday_string_is_ignored_instead_of_crashing(self):
        with override(payroll_holidays="not-a-date,2026-09-15"):
            self.assertEqual(len(work_days_in(SEP(14), SEP(26))), 9)

    def test_broken_weekday_string_falls_back_to_mon_fri(self):
        with override(payroll_work_weekdays="เก้า,,x"):
            self.assertEqual(settings.payroll_weekdays_set, {1, 2, 3, 4, 5})

    def test_six_day_week_is_supported(self):
        with override(payroll_work_weekdays="1,2,3,4,5,6"):
            self.assertEqual(len(work_days_in(SEP(14), SEP(26))), 12)


class ProrateTests(unittest.TestCase):
    """เงินรอบแรกของคนที่เริ่มงานกลางรอบ"""

    def setUp(self):
        self.period = period_containing(SEP(26))
        self.present = set(work_days_in(SEP(14), SEP(26)))

    def summary(self, **kwargs):
        base = dict(
            period=self.period,
            employee_name="ทดสอบ",
            base_salary=18000,
            employment_start=SEP(14),
            present_days=self.present,
            as_of=SEP(26),
        )
        base.update(kwargs)
        return build_summary(**base)

    def test_calendar_30_prorates_by_calendar_days(self):
        with override(payroll_prorate_basis="calendar_30"):
            summary = self.summary()
        # 14-26 ก.ย. = 13 วันตามปฏิทิน  ->  18000/30*13
        self.assertAlmostEqual(summary.gross, 7800.0, places=2)
        self.assertAlmostEqual(summary.daily_rate, 600.0, places=2)

    def test_work_days_basis_prorates_by_working_days(self):
        with override(payroll_prorate_basis="work_days"):
            summary = self.summary()
        # วันทำงานทั้งรอบ 22 วัน, มีสิทธิ์ 10 วัน -> 18000/22*10
        self.assertAlmostEqual(summary.daily_rate, 18000 / 22, places=2)
        self.assertAlmostEqual(summary.gross, 18000 / 22 * 10, places=2)

    def test_full_period_employee_gets_full_salary(self):
        with override(payroll_prorate_basis="calendar_30"):
            summary = self.summary(
                employment_start=date(2026, 1, 1),
                present_days=set(work_days_in(self.period.start, self.period.end)),
            )
        self.assertAlmostEqual(summary.gross, 18000.0, places=2)
        self.assertEqual(summary.absent_days, 0)

    def test_absence_is_deducted_at_daily_rate(self):
        with override(payroll_prorate_basis="calendar_30"):
            summary = self.summary(present_days=set(sorted(self.present)[1:]))
        self.assertEqual(summary.absent_days, 1)
        self.assertAlmostEqual(summary.deduction_absent, 600.0, places=2)
        self.assertAlmostEqual(summary.net, 7800 - 600 - 360, places=2)

    def test_starting_after_the_cutoff_earns_nothing_this_period(self):
        summary = self.summary(employment_start=date(2026, 10, 5), present_days=set())
        self.assertEqual(summary.gross, 0.0)
        self.assertEqual(summary.net, 0.0)
        self.assertEqual(summary.work_days_total, 0)

    def test_extra_days_outside_work_days_never_make_absence_negative(self):
        """มาทำงานวันเสาร์ไม่ควรทำให้ยอดเพี้ยน"""
        summary = self.summary(present_days=self.present | {SEP(19)})
        self.assertEqual(summary.absent_days, 0)
        self.assertEqual(summary.present_days, len(self.present))

    def test_as_of_mid_period_only_counts_elapsed_days(self):
        summary = self.summary(as_of=SEP(18), present_days=set(work_days_in(SEP(14), SEP(18))))
        self.assertEqual(summary.work_days_elapsed, 5)
        self.assertEqual(summary.work_days_total, 10)
        self.assertEqual(summary.absent_days, 0)
        self.assertFalse(summary.period_closed)

    def test_late_days_are_reported_but_not_deducted_by_default(self):
        summary = self.summary(late_days=set(sorted(self.present)[:3]))
        self.assertEqual(summary.late_days, 3)
        self.assertEqual(summary.deduction_late, 0.0)

    def test_late_deduction_applies_when_configured(self):
        with override(payroll_late_deduction_per_day=100):
            summary = self.summary(late_days=set(sorted(self.present)[:3]))
        self.assertAlmostEqual(summary.deduction_late, 300.0, places=2)


class SocialSecurityTests(unittest.TestCase):
    def summary_for_salary(self, salary):
        period = period_containing(SEP(26))
        return build_summary(
            period=period,
            employee_name="ทดสอบ",
            base_salary=salary,
            employment_start=date(2026, 1, 1),
            present_days=set(work_days_in(period.start, period.end)),
            as_of=period.end,
        )

    def test_capped_at_750_for_salary_above_15000(self):
        self.assertAlmostEqual(self.summary_for_salary(18000).social_security, 750.0, places=2)
        self.assertAlmostEqual(self.summary_for_salary(50000).social_security, 750.0, places=2)

    def test_five_percent_below_the_cap(self):
        self.assertAlmostEqual(self.summary_for_salary(12000).social_security, 600.0, places=2)

    def test_can_be_switched_off(self):
        with override(payroll_social_security_enabled=False):
            self.assertEqual(self.summary_for_salary(18000).social_security, 0.0)

    def test_net_never_goes_below_zero(self):
        period = period_containing(SEP(26))
        summary = build_summary(
            period=period,
            employee_name="ทดสอบ",
            base_salary=18000,
            employment_start=date(2026, 1, 1),
            present_days=set(),  # ขาดทั้งรอบ
            as_of=period.end,
        )
        self.assertGreaterEqual(summary.net, 0.0)

    def test_projected_full_period_assumes_perfect_attendance(self):
        period = period_containing(SEP(26))
        projected = projected_full_period(period, 18000, date(2026, 1, 1))
        self.assertEqual(projected.absent_days, 0)
        self.assertAlmostEqual(projected.net, 17250.0, places=2)


class FlexMessageTests(unittest.TestCase):
    def setUp(self):
        period = period_containing(SEP(26))
        self.summary = build_summary(
            period=period,
            employee_name="ทดสอบ ระบบ",
            base_salary=18000,
            employment_start=SEP(14),
            present_days=set(work_days_in(SEP(14), SEP(24))),
            late_days={SEP(15)},
            as_of=period.end,
        )

    def test_bubbles_have_the_shape_line_expects(self):
        for bubble in (
            cutoff_bubble(self.summary),
            payday_bubble(self.summary),
            cycle_start_bubble(self.summary, self.summary),
        ):
            self.assertEqual(bubble["type"], "bubble")
            self.assertEqual(bubble["header"]["type"], "box")
            self.assertEqual(bubble["body"]["type"], "box")
            self.assertTrue(bubble["body"]["contents"])

    def test_colors_are_hex_because_line_rejects_names(self):
        def walk(node):
            if isinstance(node, dict):
                for key, value in node.items():
                    if key.endswith("olor") and isinstance(value, str):
                        self.assertRegex(value, r"^#[0-9A-Fa-f]{6}$")
                    walk(value)
            elif isinstance(node, list):
                for item in node:
                    walk(item)

        walk(cutoff_bubble(self.summary))

    def test_alt_text_stays_within_line_limit(self):
        for kind in (NOTICE_CUTOFF, NOTICE_CYCLE_START, NOTICE_PAYDAY):
            self.assertLessEqual(len(alt_text(kind, self.summary)), 400)

    def test_alt_text_is_readable_not_a_placeholder(self):
        text = alt_text(NOTICE_CUTOFF, self.summary)
        self.assertIn("สุทธิ", text)
        self.assertIn("ทดสอบ ระบบ", text)


class DueNoticeTests(unittest.TestCase):
    def kinds_due(self, when: datetime) -> set[str]:
        return {kind for kind, _, _ in payroll_service.due_notices(when)}

    def test_cutoff_fires_after_its_configured_time_on_day_26(self):
        self.assertIn(NOTICE_CUTOFF, self.kinds_due(datetime(2026, 9, 26, 18, 5)))

    def test_cutoff_does_not_fire_in_the_morning_of_day_26(self):
        due = payroll_service.due_notices(datetime(2026, 9, 26, 9, 5))
        cutoffs = [period for kind, period, _ in due if kind == NOTICE_CUTOFF]
        # เช้าวันที่ 26 ยังไม่ตัดรอบ — ถ้ามี ต้องเป็นของรอบก่อนหน้า ไม่ใช่รอบนี้
        for period in cutoffs:
            self.assertNotEqual(period.end, SEP(26))

    def test_cycle_start_fires_on_day_27(self):
        kind_periods = {
            kind: period
            for kind, period, _ in payroll_service.due_notices(datetime(2026, 9, 27, 9, 5))
        }
        self.assertIn(NOTICE_CYCLE_START, kind_periods)
        self.assertEqual(kind_periods[NOTICE_CYCLE_START].start, SEP(27))

    def test_payday_fires_on_day_28_for_the_closed_period(self):
        kind_periods = {
            kind: period
            for kind, period, _ in payroll_service.due_notices(datetime(2026, 9, 28, 9, 5))
        }
        self.assertIn(NOTICE_PAYDAY, kind_periods)
        self.assertEqual(kind_periods[NOTICE_PAYDAY].end, SEP(26))

    def test_catch_up_still_fires_the_next_morning_after_a_reboot(self):
        """เซิร์ฟเวอร์ดับคืนวันที่ 26 กลับมาเช้าวันที่ 27 ต้องยังได้ข้อความตัดรอบ"""
        with override(payroll_notice_catchup_hours=36):
            self.assertIn(NOTICE_CUTOFF, self.kinds_due(datetime(2026, 9, 27, 8, 0)))

    def test_stale_notices_are_dropped_outside_the_catch_up_window(self):
        with override(payroll_notice_catchup_hours=6):
            self.assertNotIn(NOTICE_CUTOFF, self.kinds_due(datetime(2026, 9, 28, 9, 0)))

    def test_nothing_is_due_in_the_middle_of_a_period(self):
        self.assertEqual(self.kinds_due(datetime(2026, 9, 15, 12, 0)), set())


class AttendanceFromDatabaseTests(unittest.TestCase):
    """ดึงวันมาทำงานจาก checkins จริง — ต้องใช้เกณฑ์เดียวกับปฏิทินบนเว็บ"""

    def setUp(self):
        self.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        Employee.__table__.create(self.engine)
        CheckIn.__table__.create(self.engine)
        PayrollNotice.__table__.create(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        self.period = period_containing(SEP(26))

        with self.sessions() as db:
            db.add(
                Employee(
                    id=1,
                    employee_code="EMP001",
                    full_name="ทดสอบ ระบบ",
                    email="t1@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=False,
                    start_date=SEP(14),
                    base_salary=18000,
                )
            )
            db.commit()

    def tearDown(self):
        self.engine.dispose()

    def add_checkin(self, day, hour=8, minute=0, *, kind="in", office="Motta & Montipa (Head office)",
                    within=True):
        """เวลาที่ส่งเข้าเป็นเวลาไทย — แปลงกลับเป็น UTC ให้เหมือนที่ระบบเก็บจริง"""
        local = datetime.combine(day, datetime.min.time()).replace(hour=hour, minute=minute)
        with self.sessions() as db:
            db.add(
                CheckIn(
                    employee_id=1,
                    kind=kind,
                    timestamp=local - timedelta(hours=settings.timezone_offset_hours),
                    latitude=13.9,
                    longitude=100.5,
                    distance_km=0.1,
                    within_geofence=within,
                    office_name=office,
                    face_detected=True,
                )
            )
            db.commit()

    def attendance(self):
        with self.sessions() as db:
            return payroll_service.attendance_in_period(db, 1, self.period)

    def test_counts_one_day_per_date_even_with_repeat_taps(self):
        self.add_checkin(SEP(14), 8, 25)
        self.add_checkin(SEP(14), 13, 5)
        present, late, _ = self.attendance()
        self.assertEqual(present, {SEP(14)})
        self.assertEqual(late, set())  # ยึดการกดครั้งแรก ไม่ใช่ครั้งบ่าย

    def test_late_uses_the_first_tap_of_the_day(self):
        self.add_checkin(SEP(15), 8, 45)
        present, late, minutes = self.attendance()
        self.assertEqual(present, {SEP(15)})
        self.assertEqual(late, {SEP(15)})
        self.assertEqual(minutes, 15)

    def test_home_records_do_not_count_as_attendance(self):
        self.add_checkin(SEP(16), 8, 0, office="ถึงบ้านแล้ว")
        present, _, _ = self.attendance()
        self.assertEqual(present, set())

    def test_outside_geofence_does_not_count(self):
        self.add_checkin(SEP(17), 8, 0, within=False)
        present, _, _ = self.attendance()
        self.assertEqual(present, set())

    def test_checkout_records_are_not_attendance(self):
        self.add_checkin(SEP(18), 17, 40, kind="out")
        present, _, _ = self.attendance()
        self.assertEqual(present, set())

    def test_records_outside_the_period_are_excluded(self):
        self.add_checkin(SEP(27), 8, 0)   # รอบถัดไปแล้ว
        self.add_checkin(date(2026, 8, 26), 8, 0)  # รอบก่อนหน้า
        present, _, _ = self.attendance()
        self.assertEqual(present, set())

    def test_summary_uses_the_employee_start_date(self):
        for day in work_days_in(SEP(14), SEP(26)):
            self.add_checkin(day, 8, 0)
        with self.sessions() as db:
            employee = db.query(Employee).first()
            summary = payroll_service.summary_for(db, employee, self.period, as_of=SEP(26))
        self.assertEqual(summary.work_days_total, 10)
        self.assertEqual(summary.present_days, 10)
        self.assertAlmostEqual(summary.gross, 7800.0, places=2)
        self.assertAlmostEqual(summary.net, 7410.0, places=2)


class SendGuardTests(unittest.TestCase):
    """กันส่งซ้ำ — Scheduled Task ยิงวันละ 2 รอบ และคนยังกดเองได้อีก"""

    def setUp(self):
        self.engine = create_engine(
            "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
        )
        Employee.__table__.create(self.engine)
        CheckIn.__table__.create(self.engine)
        PayrollNotice.__table__.create(self.engine)
        self.sessions = sessionmaker(bind=self.engine)
        self.period = period_containing(SEP(26))
        self.sent = []

        with self.sessions() as db:
            db.add(
                Employee(
                    id=1,
                    employee_code="EMP001",
                    full_name="ทดสอบ ระบบ",
                    email="t1@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=False,
                    start_date=SEP(14),
                    base_salary=18000,
                )
            )
            db.commit()

        # ห้ามยิง LINE จริงในเทสต์
        self._real_push = payroll_service.push_flex
        self._real_ready = payroll_service.is_configured
        payroll_service.push_flex = lambda alt, contents, to=None: (
            self.sent.append(alt) or True
        )
        payroll_service.is_configured = lambda: True

    def tearDown(self):
        payroll_service.push_flex = self._real_push
        payroll_service.is_configured = self._real_ready
        self.engine.dispose()

    def send(self, **kwargs):
        with self.sessions() as db:
            employee = db.query(Employee).first()
            return payroll_service.send_notice(
                db, employee, NOTICE_CUTOFF, self.period, **kwargs
            )

    def test_second_send_in_the_same_period_is_skipped(self):
        self.assertTrue(self.send()["sent"])
        second = self.send()
        self.assertFalse(second["sent"])
        self.assertIn("ส่งไปแล้ว", second["reason"])
        self.assertEqual(len(self.sent), 1)

    def test_force_sends_again(self):
        self.send()
        self.assertTrue(self.send(force=True)["sent"])
        self.assertEqual(len(self.sent), 2)

    def test_dry_run_neither_sends_nor_records(self):
        result = self.send(dry_run=True)
        self.assertFalse(result["sent"])
        self.assertEqual(self.sent, [])
        self.assertTrue(result["text"])
        # ไม่บันทึกว่าส่งแล้ว -> ของจริงยังส่งได้อยู่
        self.assertTrue(self.send()["sent"])

    def test_failed_send_is_retried_next_run(self):
        payroll_service.push_flex = lambda alt, contents, to=None: False
        self.assertFalse(self.send()["sent"])
        payroll_service.push_flex = lambda alt, contents, to=None: (
            self.sent.append(alt) or True
        )
        self.assertTrue(self.send()["sent"])

    def test_employees_without_salary_are_not_in_payroll(self):
        with self.sessions() as db:
            db.add(
                Employee(
                    id=2,
                    employee_code="EMP002",
                    full_name="ยังไม่ตั้งเงินเดือน",
                    email="t2@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=False,
                )
            )
            db.commit()
            with override(payroll_default_salary=0):
                codes = [e.employee_code for e in payroll_service.payroll_employees(db)]
        self.assertEqual(codes, ["EMP001"])

    def test_default_salary_never_applies_to_managers(self):
        """ตั้ง PAYROLL_DEFAULT_SALARY แล้วบัญชีหัวหน้าต้องไม่โดนลากเข้าระบบเงินเดือน"""
        with self.sessions() as db:
            db.add(
                Employee(
                    id=99,
                    employee_code="BOSS001",
                    full_name="หัวหน้า",
                    email="boss@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=True,
                )
            )
            db.commit()
            with override(payroll_default_salary=18000):
                codes = sorted(e.employee_code for e in payroll_service.payroll_employees(db))
        self.assertNotIn("BOSS001", codes)

    def test_manager_with_explicit_salary_is_still_included(self):
        """ตั้งเงินเดือนให้หัวหน้าตรงๆ ต้องยังเข้าระบบได้ — กันเงื่อนไขเหมาเกินไป"""
        with self.sessions() as db:
            db.add(
                Employee(
                    id=98,
                    employee_code="BOSS002",
                    full_name="หัวหน้ามีเงินเดือน",
                    email="boss2@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=True,
                    base_salary=40000,
                )
            )
            db.commit()
            with override(payroll_default_salary=0):
                codes = sorted(e.employee_code for e in payroll_service.payroll_employees(db))
        self.assertIn("BOSS002", codes)

    def test_default_salary_pulls_everyone_in_when_set(self):
        with self.sessions() as db:
            db.add(
                Employee(
                    id=2,
                    employee_code="EMP002",
                    full_name="ใช้ค่า default",
                    email="t2@example.invalid",
                    hashed_password="not-a-real-password",
                    is_manager=False,
                )
            )
            db.commit()
            with override(payroll_default_salary=18000):
                codes = sorted(e.employee_code for e in payroll_service.payroll_employees(db))
        self.assertEqual(codes, ["EMP001", "EMP002"])

    def test_run_due_sends_nothing_when_disabled(self):
        with self.sessions() as db, override(payroll_enabled=False):
            report = payroll_service.run_due(db, now=datetime(2026, 9, 26, 18, 5))
        self.assertEqual(report["results"], [])
        self.assertEqual(self.sent, [])

    def test_run_due_sends_the_cutoff_notice_once(self):
        with self.sessions() as db:
            first = payroll_service.run_due(db, now=datetime(2026, 9, 26, 18, 5))
            second = payroll_service.run_due(db, now=datetime(2026, 9, 26, 18, 35))
        self.assertTrue(any(r["sent"] for r in first["results"]))
        self.assertFalse(any(r["sent"] for r in second["results"]))
        self.assertEqual(len(self.sent), 1)


if __name__ == "__main__":
    unittest.main()
