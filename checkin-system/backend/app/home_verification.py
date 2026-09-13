"""ตรวจหลักฐานการยืนยันตัวตนตอนอยู่บ้าน (ดู DAILY_HOME_FACE_VERIFICATION_2026-09-11.md)

**ขอบเขตของ verifier ชุดนี้ — อ่านก่อนใช้งานหรือแก้ไข**

ทำ: กันหลักฐานปลอม/หลักฐานเก่า/การใช้ซ้ำ
  - หลักฐานต้องผูกกับ challenge ที่ server ออกให้ อายุสั้น ใช้ได้ครั้งเดียว และเป็นของบัญชีนั้น
  - ไฟล์ต้องเป็นรูปจริงตามโครง JPEG/PNG และใหญ่พอที่จะเป็นภาพใบหน้า
  - ไบต์ของรูปต้องไม่เคยถูกใช้ยืนยันมาก่อน (กันส่งรูปเดิมซ้ำเพื่อสร้างรายการใหม่)

ไม่ทำ: **ไม่ได้เทียบว่าใบหน้าในรูปเป็นเจ้าของบัญชีจริงหรือไม่**
  ไม่มี face detection หรือ 1:1 matching ฝั่ง server — ตรงกับข้อจำกัดที่บันทึกไว้ว่า
  ระบบปัจจุบันเป็น detection + liveness ฝั่งอุปกรณ์ ไม่ใช่การยืนยันตัวบุคคล
  ถ้าจะเพิ่มการเทียบใบหน้าจริง ให้ต่อที่ `verify_evidence()` โดยไม่ต้องแก้ router

จงใจไม่ใช้ Pillow/OpenCV: ทั้งคู่ไม่ได้ประกาศใน requirements ของโปรเจกต์นี้
ถ้า import แล้ว production ไม่มี ทั้ง backend จะไม่สตาร์ต — อ่านหัวไฟล์เองปลอดภัยกว่า
"""
import hashlib
import secrets

# คำสั่งที่สุ่มให้ผู้ใช้ทำตอนสแกน — ส่งไปกับ challenge เพื่อให้แอปแสดงและใช้ตรวจ
# liveness บนอุปกรณ์ server บันทึกไว้ว่าออกคำสั่งใด แต่ **ตรวจท่าทางในรูปไม่ได้**
#
# แต่ละรายการเป็น (รหัสสำหรับเครื่องอ่าน, ข้อความสำหรับคนอ่าน)
# รหัสมีไว้ให้แอปเลือกวิธีตรวจโดยไม่ต้องเดาจากข้อความไทย ซึ่งจะพังทันที
# ถ้าวันหลังแก้คำหรือเพิ่มภาษา
CHALLENGE_ACTIONS = (
    ("look_straight", "หันหน้าตรงกล้อง"),
    ("turn_left", "หันหน้าไปทางซ้ายช้า ๆ"),
    ("turn_right", "หันหน้าไปทางขวาช้า ๆ"),
    ("blink", "กะพริบตา 2 ครั้ง"),
)

# นามสกุลไฟล์ตามชนิดรูปที่ยอมรับ
_EXTENSIONS = {"jpeg": ".jpg", "png": ".png"}


class EvidenceError(ValueError):
    """หลักฐานใช้ไม่ได้ — `code` ใช้ให้แอปแสดงวิธีแก้ที่ตรงกับสาเหตุ"""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def pick_action() -> tuple[str, str]:
    """สุ่มคำสั่ง คืน (รหัส, ข้อความ)"""
    return secrets.choice(CHALLENGE_ACTIONS)


def action_code_of(action: str) -> str | None:
    """หารหัสจากข้อความ — ใช้กับ challenge เก่าที่บันทึกไว้ก่อนมีคอลัมน์รหัส"""
    for code, text in CHALLENGE_ACTIONS:
        if text == action:
            return code
    return None


def _png_size(data: bytes) -> tuple[int, int] | None:
    # PNG: signature 8 ไบต์ แล้ว IHDR chunk ที่มี width/height เป็น big-endian 4 ไบต์
    if len(data) < 24 or not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return None
    if data[12:16] != b"IHDR":
        return None
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return width, height


def _jpeg_size(data: bytes) -> tuple[int, int] | None:
    # JPEG: ไล่ marker ทีละ segment จนเจอ SOF (Start Of Frame) ที่เก็บขนาดภาพ
    if len(data) < 4 or not data.startswith(b"\xff\xd8"):
        return None
    i = 2
    end = len(data)
    while i + 9 < end:
        if data[i] != 0xFF:
            i += 1  # ข้าม byte stuffing / ขยะระหว่าง segment
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2  # marker ที่ไม่มีความยาวตามหลัง
            continue
        if marker == 0xD9 or marker == 0xDA:
            return None  # จบไฟล์/เริ่มข้อมูลภาพแล้วแต่ยังไม่เจอ SOF
        length = int.from_bytes(data[i + 2 : i + 4], "big")
        if length < 2:
            return None
        # SOF0-SOF15 ยกเว้น DHT(C4) / JPG(C8) / DAC(CC)
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height = int.from_bytes(data[i + 5 : i + 7], "big")
            width = int.from_bytes(data[i + 7 : i + 9], "big")
            return width, height
        i += 2 + length
    return None


def image_info(data: bytes) -> tuple[str, int, int] | None:
    """คืน (ชนิด, กว้าง, สูง) ถ้าไบต์ชุดนี้เป็นรูป JPEG/PNG ที่อ่านโครงได้"""
    size = _png_size(data)
    if size:
        return ("png", *size)
    size = _jpeg_size(data)
    if size:
        return ("jpeg", *size)
    return None


def evidence_extension(image_format: str) -> str:
    return _EXTENSIONS.get(image_format, ".jpg")


def verify_evidence(
    data: bytes, *, max_bytes: int, min_pixels: int
) -> tuple[str, str, int, int]:
    """ตรวจไฟล์หลักฐานและคืน (sha256, ชนิด, กว้าง, สูง)

    ยกเว้น `EvidenceError` พร้อม code เมื่อใช้ไม่ได้ ตัว sha256 ที่คืนไปใช้กัน
    การส่งรูปเดิมซ้ำ — ผู้เรียกต้องเช็คว่าเคยถูกใช้ยืนยันมาก่อนหรือไม่
    """
    if not data:
        raise EvidenceError("evidence_invalid", "ไม่พบไฟล์หลักฐาน กรุณาสแกนใหม่")
    if len(data) > max_bytes:
        raise EvidenceError(
            "evidence_invalid",
            f"ไฟล์หลักฐานใหญ่เกิน {max_bytes // 1_000_000} MB กรุณาสแกนใหม่",
        )

    info = image_info(data)
    if info is None:
        raise EvidenceError(
            "evidence_invalid", "ไฟล์หลักฐานไม่ใช่รูปภาพ JPEG/PNG กรุณาสแกนใหม่"
        )

    image_format, width, height = info
    if min(width, height) < min_pixels:
        raise EvidenceError(
            "evidence_invalid",
            f"ภาพเล็กเกินไป ({width}x{height}) ต้องมีด้านสั้นอย่างน้อย {min_pixels} พิกเซล",
        )

    return hashlib.sha256(data).hexdigest(), image_format, width, height


def payload_fingerprint(
    challenge_id: str, latitude: float, longitude: float, evidence_sha256: str
) -> str:
    """ลายนิ้วมือของคำขอ ใช้ดูว่า request_id เดิมถูกส่งซ้ำด้วยเนื้อหาเดิมจริงหรือไม่

    ปัดพิกัดให้หยาบระดับ ~1 เมตร เพื่อไม่ให้ GPS ที่สั่นเล็กน้อยตอนส่งซ้ำ
    กลายเป็น "เปลี่ยน payload" แล้วโดนปฏิเสธทั้งที่เป็นคำขอเดียวกัน
    """
    raw = f"{challenge_id}|{latitude:.5f}|{longitude:.5f}|{evidence_sha256}"
    return hashlib.sha256(raw.encode()).hexdigest()
