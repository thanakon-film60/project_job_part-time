"""ตัดสินว่าการลงเวลาครั้งนี้ "สาย" หรือ "ตรงเวลา"

เกณฑ์มาจาก .env (WORK_START_TIME / WORK_END_TIME / *_GRACE_MINUTES) ไม่ได้ฝังไว้
ในโค้ด เพราะบริษัทเปลี่ยนเวลาทำงานได้โดยไม่ต้อง build แอปใหม่

โมดูลนี้ไม่แตะฐานข้อมูลและไม่รู้จัก SQLAlchemy — รับเวลาไทยเข้ามาแล้วคืนผลอย่างเดียว
จึงเรียกได้ทั้งจาก background task ของ LINE และจากที่อื่นในอนาคต

หมายเหตุเรื่องข้ามเที่ยงคืน: ระบบนี้เป็นกะกลางวัน (08:30-17:30) การเทียบจึงดูแค่
"เวลาในวัน" ไม่ได้ดูวันที่ ลงเวลาตอนตี 1 จะถือว่ามาก่อนเวลา ไม่ใช่สายข้ามวัน
"""
from dataclasses import dataclass
from datetime import datetime, time

from .config import settings
from .geofence import location_category

# ค่า status ที่เป็นไปได้ — ฝั่งแอปใช้สตริงชุดเดียวกันนี้ (work_schedule.dart)
STATUS_ON_TIME = "on_time"
STATUS_LATE = "late"
STATUS_EARLY_LEAVE = "early_leave"
STATUS_COMPLETE = "complete"
STATUS_NOT_APPLICABLE = "not_applicable"


@dataclass(frozen=True)
class AttendanceVerdict:
    """ผลตัดสินการลงเวลา 1 ครั้ง"""

    status: str

    # จำนวนนาทีที่ "สาย" หรือ "ออกก่อน" (0 ถ้าไม่เข้าเงื่อนไขนั้น)
    minutes: int

    # ข้อความสั้นสำหรับแสดงผล/ส่ง LINE เช่น "สาย 12 นาที"
    label: str

    @property
    def is_late(self) -> bool:
        return self.status == STATUS_LATE

    @property
    def is_early_leave(self) -> bool:
        return self.status == STATUS_EARLY_LEAVE

    @property
    def applies(self) -> bool:
        """มีเกณฑ์ให้ตัดสินไหม (False = อยู่บ้าน หรือปิดฟีเจอร์ไว้)"""
        return self.status != STATUS_NOT_APPLICABLE


def _minutes_of_day(value: time) -> int:
    return value.hour * 60 + value.minute


def _human_minutes(total: int) -> str:
    """12 -> "12 นาที" / 95 -> "1 ชม. 35 นาที" """
    hours, minutes = divmod(max(total, 0), 60)
    if hours == 0:
        return f"{minutes} นาที"
    if minutes == 0:
        return f"{hours} ชม."
    return f"{hours} ชม. {minutes} นาที"


def _not_applicable() -> AttendanceVerdict:
    return AttendanceVerdict(status=STATUS_NOT_APPLICABLE, minutes=0, label="")


def evaluate_attendance(
    kind: str,
    local_time: datetime,
    office: dict | None = None,
) -> AttendanceVerdict:
    """ตัดสินการลงเวลา 1 ครั้ง

    [local_time] ต้องเป็น "เวลาไทย" แล้ว (บวก timezone_offset_hours มาก่อน)
    ไม่ใช่ UTC ดิบจาก DB — ไม่งั้นทุกคนจะสายเกินจริง 7 ชั่วโมง

    [office] ใส่มาเพื่อข้ามการตัดสินเมื่อลงเวลาที่บ้าน (อยู่บ้าน = ไม่ได้ไปทำงาน
    จึงไม่มีสาย/ไม่มีออกก่อน — ตรรกะเดียวกับ notify_checkin)
    """
    if not settings.attendance_rules_enabled:
        return _not_applicable()
    if office is not None and location_category(office) == "home":
        return _not_applicable()

    now_minutes = _minutes_of_day(local_time.time())

    if kind == "in":
        start = _minutes_of_day(settings.work_start)
        # ผ่อนผันเป็นแค่ "เส้นตัดสิน" ว่าจะเรียกว่าสายไหม แต่จำนวนนาทีที่รายงาน
        # นับจากเวลาเข้างานจริง (08:30) เพราะนั่นคือตัวเลขที่ HR ใช้
        deadline = start + settings.late_grace_minutes
        if now_minutes > deadline:
            late_by = now_minutes - start
            return AttendanceVerdict(
                status=STATUS_LATE,
                minutes=late_by,
                label=f"สาย {_human_minutes(late_by)}",
            )
        early_by = start - now_minutes
        label = (
            "ตรงเวลา"
            if early_by <= 0
            else f"ตรงเวลา (ก่อนเวลา {_human_minutes(early_by)})"
        )
        return AttendanceVerdict(
            status=STATUS_ON_TIME, minutes=0, label=label
        )

    if kind == "out":
        end = _minutes_of_day(settings.work_end)
        threshold = end - settings.early_leave_grace_minutes
        if now_minutes < threshold:
            early_by = end - now_minutes
            return AttendanceVerdict(
                status=STATUS_EARLY_LEAVE,
                minutes=early_by,
                label=f"ออกก่อนเวลา {_human_minutes(early_by)}",
            )
        overtime = now_minutes - end
        label = (
            "ครบเวลางาน"
            if overtime <= 0
            else f"ครบเวลางาน (เกินเวลา {_human_minutes(overtime)})"
        )
        return AttendanceVerdict(
            status=STATUS_COMPLETE, minutes=max(overtime, 0), label=label
        )

    return _not_applicable()


def schedule_text() -> str:
    """ข้อความบอกเวลาทำงานมาตรฐาน ใช้ต่อท้ายข้อความแจ้งเตือน"""
    start = settings.work_start.strftime("%H:%M")
    end = settings.work_end.strftime("%H:%M")
    return f"เวลาทำงาน {start} - {end} น."
