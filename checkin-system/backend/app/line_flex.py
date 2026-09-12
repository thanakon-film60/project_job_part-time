"""สร้างการ์ด Flex Message ของ LINE สำหรับสรุปเงินเดือน

**ไม่ต้องลงไลบรารีเพิ่ม** — Flex Message เป็นของที่ Messaging API มีให้อยู่แล้ว
(ตัวเดียวกับที่ระบบใช้ push_text อยู่) แค่ส่ง JSON คนละรูปแบบเท่านั้น
การลง line-bot-sdk จะลาก aiohttp/requests เข้ามาโดยไม่ได้อะไรเพิ่ม เพราะ
notify_line.py ยิง HTTP ด้วย urllib จาก stdlib อยู่แล้ว

เอกสารโครงสร้าง: https://developers.line.biz/en/docs/messaging-api/flex-message-elements/

ข้อจำกัดที่ต้องระวัง:
  - altText ยาวได้ 400 ตัวอักษร (เกินแล้ว LINE ตีกลับทั้งข้อความ)
  - 1 bubble มี header/hero/body/footer ได้อย่างละ 1
  - สีต้องเป็น #RRGGBB เท่านั้น ชื่อสีอย่าง "red" ใช้ไม่ได้
"""

from .payroll import PayrollSummary, baht, thai_date
from .payroll_models import NOTICE_CUTOFF, NOTICE_CYCLE_START, NOTICE_PAYDAY

# สีประจำข้อความแต่ละแบบ — ให้แยกออกจากกันได้ตั้งแต่ยังไม่อ่านตัวหนังสือ
THEME = {
    NOTICE_CUTOFF: {"color": "#0F766E", "emoji": "🧾", "title": "ตัดรอบแล้ว"},
    NOTICE_CYCLE_START: {"color": "#1D4ED8", "emoji": "🚀", "title": "เริ่มรอบใหม่"},
    NOTICE_PAYDAY: {"color": "#15803D", "emoji": "💰", "title": "วันเงินเดือนออก"},
}

_GREY = "#8C8C8C"
_TEXT = "#222222"
_RED = "#C0392B"


def _text(value: str, *, size="sm", color=_TEXT, weight=None, align=None, wrap=True):
    node = {"type": "text", "text": str(value), "size": size, "color": color, "wrap": wrap}
    if weight:
        node["weight"] = weight
    if align:
        node["align"] = align
    return node


def _row(label: str, value: str, *, value_color=_TEXT, bold=False):
    """หนึ่งบรรทัด: ป้ายซ้าย ตัวเลขขวา — ตัวเลขชิดขวาเสมอเพื่อให้กวาดตาอ่านง่าย"""
    return {
        "type": "box",
        "layout": "horizontal",
        "contents": [
            _text(label, size="sm", color=_GREY, wrap=False),
            _text(
                value,
                size="sm",
                color=value_color,
                weight="bold" if bold else None,
                align="end",
                wrap=False,
            ),
        ],
    }


def _separator():
    return {"type": "separator", "margin": "md", "color": "#E5E5E5"}


def _header(kind: str, subtitle: str):
    theme = THEME[kind]
    return {
        "type": "box",
        "layout": "vertical",
        "backgroundColor": theme["color"],
        "paddingAll": "16px",
        "spacing": "xs",
        "contents": [
            _text(
                f"{theme['emoji']} {theme['title']}",
                size="lg",
                color="#FFFFFF",
                weight="bold",
            ),
            _text(subtitle, size="xs", color="#E8F5F3"),
        ],
    }


def _amount_block(caption: str, amount: float, *, color: str):
    return {
        "type": "box",
        "layout": "vertical",
        "spacing": "none",
        "contents": [
            _text(caption, size="xs", color=_GREY),
            _text(f"฿{baht(amount)}", size="3xl", color=color, weight="bold"),
        ],
    }


def _footer(lines: list[str]):
    if not lines:
        return None
    return {
        "type": "box",
        "layout": "vertical",
        "paddingAll": "12px",
        "spacing": "xs",
        "backgroundColor": "#FAFAFA",
        "contents": [_text(line, size="xxs", color=_GREY) for line in lines],
    }


def _bubble(kind: str, subtitle: str, body_contents: list, footer_lines: list[str]):
    bubble = {
        "type": "bubble",
        "header": _header(kind, subtitle),
        "body": {
            "type": "box",
            "layout": "vertical",
            "spacing": "md",
            "paddingAll": "16px",
            "contents": body_contents,
        },
    }
    footer = _footer(footer_lines)
    if footer:
        bubble["footer"] = footer
    return bubble


def _days_until(summary: PayrollSummary) -> str:
    left = (summary.period.payday - summary.as_of).days
    if left > 0:
        return f"อีก {left} วัน"
    if left == 0:
        return "วันนี้"
    return ""


def _attendance_rows(summary: PayrollSummary) -> list:
    rows = [
        _row("วันทำงานในรอบ", f"{summary.work_days_total} วัน"),
        _row("มาทำงานแล้ว", f"{summary.present_days} วัน"),
    ]
    if summary.absent_days:
        rows.append(_row("ขาดงาน", f"{summary.absent_days} วัน", value_color=_RED, bold=True))
    if summary.late_days:
        rows.append(_row("มาสาย", f"{summary.late_days} วัน", value_color=_RED))
    return rows


def _money_rows(summary: PayrollSummary) -> list:
    rows = [_row("รายได้ก่อนหัก", f"฿{baht(summary.gross)}")]
    if summary.deduction_absent:
        rows.append(
            _row("หักขาดงาน", f"-฿{baht(summary.deduction_absent)}", value_color=_RED)
        )
    if summary.deduction_late:
        rows.append(
            _row("หักมาสาย", f"-฿{baht(summary.deduction_late)}", value_color=_RED)
        )
    if summary.social_security:
        rows.append(
            _row("ประกันสังคม", f"-฿{baht(summary.social_security)}", value_color=_RED)
        )
    return rows


# ---------------------------------------------------------------------------
# การ์ดแต่ละแบบ
# ---------------------------------------------------------------------------


def cutoff_bubble(summary: PayrollSummary) -> dict:
    """วันที่ 26 — ตัดรอบแล้ว บอกว่ารอบนี้จะได้เงินเท่าไร"""
    body = [
        _amount_block("คาดว่าจะได้รับรอบนี้", summary.net, color=THEME[NOTICE_CUTOFF]["color"]),
        _text(
            f"เข้าบัญชี {thai_date(summary.period.payday)} ({_days_until(summary)})",
            size="xs",
            color=_GREY,
        ),
        _separator(),
        *_attendance_rows(summary),
        _separator(),
        *_money_rows(summary),
        _separator(),
        _row("ยอดสุทธิ", f"฿{baht(summary.net)}", bold=True),
    ]
    footer = list(summary.notes)
    footer.append("ตัวเลขนี้เป็นการประมาณจากการลงเวลาในระบบ ยอดจริงยึดตามฝ่ายบุคคล")
    return _bubble(NOTICE_CUTOFF, f"รอบ {summary.period.label}", body, footer)


def cycle_start_bubble(summary: PayrollSummary, projected: PayrollSummary) -> dict:
    """วันที่ 27 — รอบใหม่เริ่มแล้ว บอกเป้าหมายและวันจ่ายถัดไป"""
    body = [
        _amount_block(
            "ถ้ามาครบทุกวัน จะได้", projected.net, color=THEME[NOTICE_CYCLE_START]["color"]
        ),
        _text(
            f"จ่าย {thai_date(summary.period.payday)}",
            size="xs",
            color=_GREY,
        ),
        _separator(),
        _row("รอบใหม่", summary.period.label),
        _row("ต้องมาทำงาน", f"{summary.work_days_total} วัน"),
        _row("ค่าแรงต่อวัน", f"฿{baht(summary.daily_rate)}"),
        _separator(),
        _row("รายได้ก่อนหัก", f"฿{baht(projected.gross)}"),
    ] + (
        [_row("ประกันสังคม", f"-฿{baht(projected.social_security)}", value_color=_RED)]
        if projected.social_security
        else []
    )
    footer = ["ขาด 1 วัน หัก ฿" + baht(summary.daily_rate) + " — มาครบไม่มีหัก"]
    footer.extend(summary.notes)
    return _bubble(NOTICE_CYCLE_START, "เริ่มนับรอบใหม่วันนี้", body, footer)


def payday_bubble(summary: PayrollSummary) -> dict:
    """วันที่ 28 — เงินออกวันนี้ สรุปว่าได้เท่าไรและมาจากไหน"""
    body = [
        _amount_block("เงินเข้าวันนี้", summary.net, color=THEME[NOTICE_PAYDAY]["color"]),
        _text(f"ของรอบ {summary.period.label}", size="xs", color=_GREY),
        _separator(),
        *_attendance_rows(summary),
        _separator(),
        *_money_rows(summary),
        _separator(),
        _row("รับจริง", f"฿{baht(summary.net)}", bold=True),
    ]
    footer = ["ยอดจริงยึดตามสลิปเงินเดือนจากฝ่ายบุคคล"]
    footer.extend(summary.notes)
    return _bubble(NOTICE_PAYDAY, "วันเงินเดือนออก", body, footer)


BUILDERS = {
    NOTICE_CUTOFF: cutoff_bubble,
    NOTICE_PAYDAY: payday_bubble,
}


# ---------------------------------------------------------------------------
# ข้อความตัวอักษรล้วน — ใช้เป็น altText และใช้ตอน --dry-run
# ---------------------------------------------------------------------------


def summary_text(kind: str, summary: PayrollSummary) -> str:
    """ข้อความแบบตัวอักษรล้วนที่อ่านรู้เรื่องแม้ไม่มี Flex

    ใช้สองที่: altText (ที่โผล่ในรายการแชท/นาฬิกา) และตอนสั่ง --dry-run
    ในเทอร์มินัล จึงต้องอ่านเข้าใจได้ด้วยตัวเองโดยไม่ต้องเห็นการ์ด
    """
    theme = THEME[kind]
    lines = [f"{theme['emoji']} {theme['title']} — รอบ {summary.period.label}"]

    if summary.employee_name:
        lines.append(f"พนักงาน: {summary.employee_name}")

    if kind == NOTICE_CYCLE_START:
        lines.append(f"ต้องมาทำงาน {summary.work_days_total} วัน")
        lines.append(f"ค่าแรงต่อวัน ฿{baht(summary.daily_rate)}")
        lines.append(f"จ่ายวันที่ {thai_date(summary.period.payday)}")
    else:
        lines.append(
            f"มาทำงาน {summary.present_days}/{summary.work_days_elapsed} วัน"
            + (f" · ขาด {summary.absent_days} วัน" if summary.absent_days else "")
            + (f" · สาย {summary.late_days} วัน" if summary.late_days else "")
        )
        lines.append(f"รายได้ก่อนหัก ฿{baht(summary.gross)}")
        if summary.deduction_absent:
            lines.append(f"หักขาดงาน -฿{baht(summary.deduction_absent)}")
        if summary.deduction_late:
            lines.append(f"หักมาสาย -฿{baht(summary.deduction_late)}")
        if summary.social_security:
            lines.append(f"ประกันสังคม -฿{baht(summary.social_security)}")
        lines.append(f"สุทธิ ฿{baht(summary.net)}")
        if kind == NOTICE_CUTOFF:
            lines.append(f"เข้าบัญชี {thai_date(summary.period.payday)}")

    return "\n".join(lines)


def alt_text(kind: str, summary: PayrollSummary) -> str:
    """altText ของ LINE ยาวได้ 400 ตัวอักษร — ตัดกันโดนตีกลับทั้งข้อความ"""
    return summary_text(kind, summary)[:390]
