"""ยืนยันตัวตนรายวันตอนไม่ได้ไปทำงาน (ดู DAILY_HOME_FACE_VERIFICATION_2026-09-11.md)

หลักที่ยึดตลอดไฟล์นี้:
- อยู่บ้าน = ไม่ได้ไปทำงาน จึง **ไม่มีเวลาเข้า-ออก ไม่มีสาย/ตรงเวลา ไม่มีชั่วโมงทำงาน**
  `verified_at` เรียกว่า "เวลายืนยันตัวตน" เท่านั้น
- **ไม่ยกเว้นบัญชีหัวหน้า** ต่างจาก `POST /checkins` ที่ยกเว้นการตรวจใบหน้าให้ is_manager
- ไม่เชื่อค่าที่ client ประกาศเอง (ไม่มีฟิลด์ face_detected ใน endpoint นี้เลย)
  คำตัดสินมาจาก challenge ของ server + ไบต์ของรูปจริง + geofence ที่ server คำนวณเอง
"""
import logging
import os
import shutil
import uuid
from datetime import date as date_cls, datetime, time, timedelta

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Query,
    Response,
    UploadFile,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..geofence import evaluate_location, location_category
from ..home_verification import (
    EvidenceError,
    evidence_extension,
    payload_fingerprint,
    pick_action,
    verify_evidence,
)
from ..home_verification_models import HomeVerification, HomeVerificationChallenge
from ..models import Employee, FaceProfile
from ..notify_line import push_text
from ..security import get_current_employee, require_manager

router = APIRouter(prefix="/home-verifications", tags=["home-verifications"])
log = logging.getLogger("home_verifications")

LOCAL_OFFSET = timedelta(hours=settings.timezone_offset_hours)
TIMEZONE_NAME = "Asia/Bangkok"


def _fail(status_code: int, code: str, message: str) -> HTTPException:
    """error ที่แอปแยกสาเหตุได้ — ใช้ `code` เลือกวิธีแก้ที่จะแสดงให้ผู้ใช้"""
    return HTTPException(status_code=status_code, detail={"code": code, "message": message})


def _local_now(moment: datetime) -> datetime:
    return moment + LOCAL_OFFSET


def _iso_utc(moment: datetime | None) -> str | None:
    return moment.replace(microsecond=0).isoformat() + "Z" if moment else None


def verification_out(row: HomeVerification) -> dict:
    """รูปแบบเดียวที่ทั้งเว็บและ Flutter ใช้

    จงใจไม่มี late_minutes / expected_check_in / expected_check_out / work_hours
    """
    return {
        "id": row.id,
        "request_id": row.request_id,
        "status": row.status,
        "category": row.category,
        "office_name": row.office_name,
        "verified_at": _iso_utc(row.verified_at),
        "local_date": row.local_date.isoformat(),
        "timezone": TIMEZONE_NAME,
        "distance_km": round(row.distance_km, 4),
        "location_accuracy_m": row.location_accuracy_m,
    }


def notify_home_verification(employee_name: str, verified_at: datetime, office_name: str | None) -> None:
    """แจ้งหัวหน้าทาง LINE — ต้องไม่ใช้ถ้อยคำที่อ่านแล้วเข้าใจว่าเข้างานที่สำนักงาน"""
    try:
        local_time = _local_now(verified_at)
        push_text(
            "\n".join(
                [
                    f"{employee_name} ยืนยันตัวตนแล้ว — อยู่บ้าน / ไม่ได้ไปทำงาน",
                    f"เวลายืนยันตัวตน: {local_time.strftime('%H:%M น. %d/%m/%Y')}",
                    f"สถานที่: {office_name or '-'}",
                    "ไม่นับเป็นการเข้างาน ไม่มีเวลาเข้า-ออก และไม่คิดชั่วโมงทำงาน",
                ]
            )
        )
    except Exception as e:  # LINE ล่มต้องไม่ทำให้การยืนยันล้มเหลว
        log.warning("แจ้งเตือน LINE (home verification) ไม่สำเร็จ: %s", e)


@router.post("/challenges")
def create_challenge(
    response: Response,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ขอโจทย์ใหม่ก่อนเปิดกล้อง — ทุกการยืนยันรอบใหม่ต้องขอใหม่เสมอ"""
    response.headers["Cache-Control"] = "no-store"

    now = datetime.utcnow()
    challenge = HomeVerificationChallenge(
        challenge_id=str(uuid.uuid4()),
        employee_id=emp.id,
        action=pick_action(),
        created_at=now,
        expires_at=now + timedelta(seconds=settings.home_verification_challenge_ttl_seconds),
    )
    db.add(challenge)
    db.commit()
    db.refresh(challenge)

    has_face = (
        db.query(FaceProfile.id).filter(FaceProfile.employee_id == emp.id).first() is not None
    )
    return {
        "challenge_id": challenge.challenge_id,
        "action": challenge.action,
        "expires_at": _iso_utc(challenge.expires_at),
        "server_time": _iso_utc(now),
        "ttl_seconds": settings.home_verification_challenge_ttl_seconds,
        "timezone": TIMEZONE_NAME,
        # แอปใช้พาผู้ใช้ไปลงทะเบียนใบหน้าก่อน แทนที่จะให้สแกนแล้วค่อยโดนปฏิเสธ
        "face_enrolled": has_face,
        "evidence": {
            "photo_required": True,
            "formats": ["image/jpeg", "image/png"],
            "min_pixels": settings.home_verification_min_photo_pixels,
            "max_bytes": settings.home_verification_max_photo_bytes,
        },
    }


@router.post("")
def submit_verification(
    background_tasks: BackgroundTasks,
    response: Response,
    request_id: str = Form(...),
    challenge_id: str = Form(...),
    latitude: float = Form(...),
    longitude: float = Form(...),
    location_accuracy_m: float | None = Form(None),
    photo: UploadFile = File(...),
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    response.headers["Cache-Control"] = "no-store"

    request_id = (request_id or "").strip()
    challenge_id = (challenge_id or "").strip()
    if not request_id or len(request_id) > 36:
        raise _fail(422, "request_invalid", "request_id ไม่ถูกต้อง")

    data = photo.file.read()
    try:
        evidence_sha256, image_format, _, _ = verify_evidence(
            data,
            max_bytes=settings.home_verification_max_photo_bytes,
            min_pixels=settings.home_verification_min_photo_pixels,
        )
    except EvidenceError as err:
        raise _fail(422, err.code, err.message)

    fingerprint = payload_fingerprint(challenge_id, latitude, longitude, evidence_sha256)

    # 1) คำขอเดิมที่บันทึกไว้แล้วต้องคืนผลเดิมก่อนเสมอ — ก่อนตรวจ challenge ด้วยซ้ำ
    #    เพราะกรณีนี้คือ "ส่งสำเร็จแต่ response หาย" ซึ่ง challenge ถูกใช้ไปแล้วแน่นอน
    existing = (
        db.query(HomeVerification)
        .filter_by(employee_id=emp.id, request_id=request_id)
        .first()
    )
    if existing is not None:
        if existing.payload_fingerprint != fingerprint:
            raise _fail(
                409,
                "request_conflict",
                "รหัสคำขอนี้ถูกใช้กับข้อมูลชุดอื่นแล้ว กรุณาเริ่มการยืนยันรอบใหม่",
            )
        return verification_out(existing)

    # 2) challenge ต้องเป็นของบัญชีนี้ ยังไม่หมดอายุ และยังไม่ถูกใช้
    challenge = (
        db.query(HomeVerificationChallenge)
        .filter_by(challenge_id=challenge_id, employee_id=emp.id)
        .first()
    )
    if challenge is None:
        raise _fail(422, "challenge_invalid", "ไม่พบโจทย์การยืนยันของบัญชีนี้ กรุณาเริ่มใหม่")
    if challenge.used_at is not None:
        raise _fail(409, "challenge_used", "โจทย์นี้ถูกใช้ยืนยันไปแล้ว กรุณาเริ่มการยืนยันรอบใหม่")
    if challenge.expires_at <= datetime.utcnow():
        raise _fail(422, "challenge_expired", "โจทย์การยืนยันหมดอายุแล้ว กรุณาสแกนใหม่")

    # 3) ต้องมีใบหน้าอ้างอิงก่อน — การลงทะเบียนใบหน้าไม่ใช่การยืนยันรายวัน
    #    แต่ถ้ายังไม่มีเลย ก็ไม่มีอะไรให้ตรวจย้อนหลังได้
    has_face = (
        db.query(FaceProfile.id).filter(FaceProfile.employee_id == emp.id).first() is not None
    )
    if not has_face:
        raise _fail(
            422,
            "face_not_enrolled",
            "ยังไม่ได้ลงทะเบียนใบหน้า กรุณาลงทะเบียนก่อนแล้วสแกนใหม่เพื่อยืนยันสถานะ",
        )

    # 4) รูปเดิมห้ามถูกใช้ยืนยันซ้ำ (ตรวจก่อนเขียนไฟล์ เพื่อไม่ให้เหลือขยะในดิสก์)
    if db.query(HomeVerification.id).filter_by(evidence_sha256=evidence_sha256).first():
        raise _fail(
            422,
            "evidence_reused",
            "หลักฐานนี้ถูกใช้ยืนยันไปแล้ว กรุณาสแกนใบหน้าใหม่สำหรับรอบนี้",
        )

    # 5) ตำแหน่ง — server ตัดสินเอง ต้องอยู่ในเขตและเป็นสถานที่ประเภทบ้าน
    distance_km, within, office = evaluate_location(latitude, longitude)
    if not within or location_category(office) != "home":
        raise _fail(
            422,
            "outside_home",
            f"ยืนยันสถานะที่บ้านไม่ได้เพราะอยู่นอกพื้นที่บ้านที่กำหนด — "
            f"ใกล้สุดคือ {office['name']} ห่าง {distance_km:.2f} กม.",
        )

    verified_at = datetime.utcnow()
    photo_path = None
    os.makedirs(settings.storage_dir, exist_ok=True)
    fname = f"home_{emp.employee_code}_{uuid.uuid4().hex}{evidence_extension(image_format)}"
    full = os.path.join(settings.storage_dir, fname)
    with open(full, "wb") as f:
        f.write(data)
    photo_path = full

    record = HomeVerification(
        employee_id=emp.id,
        request_id=request_id,
        challenge_id=challenge_id,
        status="verified",
        latitude=latitude,
        longitude=longitude,
        location_accuracy_m=location_accuracy_m,
        distance_km=distance_km,
        office_name=office["name"],
        category="home",
        evidence_sha256=evidence_sha256,
        payload_fingerprint=fingerprint,
        photo_path=photo_path,
        verified_at=verified_at,
        local_date=_local_now(verified_at).date(),
    )
    challenge.used_at = verified_at
    db.add(record)
    try:
        db.commit()
    except IntegrityError:
        # สองคำขอพร้อมกันด้วย request_id เดียวกัน (หรือรูปเดียวกัน) — ตัวที่แพ้
        # ต้องคืนผลของตัวที่ชนะ ไม่ใช่รายงานว่าล้มเหลว
        db.rollback()
        if os.path.exists(full):
            os.remove(full)
        winner = (
            db.query(HomeVerification)
            .filter_by(employee_id=emp.id, request_id=request_id)
            .first()
        )
        if winner is None:
            raise _fail(
                422,
                "evidence_reused",
                "หลักฐานนี้ถูกใช้ยืนยันไปแล้ว กรุณาสแกนใบหน้าใหม่สำหรับรอบนี้",
            )
        if winner.payload_fingerprint != fingerprint:
            raise _fail(
                409,
                "request_conflict",
                "รหัสคำขอนี้ถูกใช้กับข้อมูลชุดอื่นแล้ว กรุณาเริ่มการยืนยันรอบใหม่",
            )
        return verification_out(winner)

    db.refresh(record)
    background_tasks.add_task(
        notify_home_verification,
        (emp.full_name or "").strip() or emp.employee_code,
        record.verified_at,
        record.office_name,
    )
    return verification_out(record)


@router.get("/requests/{request_id}")
def verification_by_request(
    request_id: str,
    response: Response,
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ตรวจผลคำขอเดิม — ใช้ตอนส่งแล้วเน็ตหลุดจนไม่รู้ว่าบันทึกไปหรือยัง

    ไม่พบ **ไม่ได้แปลว่าคำขอแรกล้มเหลวแน่นอน** แอปต้องส่ง request_id เดิมซ้ำได้
    อย่างปลอดภัย (endpoint หลักคืนรายการเดิมให้อยู่แล้ว)
    """
    response.headers["Cache-Control"] = "no-store"
    row = (
        db.query(HomeVerification)
        .filter_by(employee_id=emp.id, request_id=request_id.strip())
        .first()
    )
    if row is None:
        raise _fail(404, "request_not_found", "ยังไม่พบผลของคำขอนี้")
    return verification_out(row)


def _resolve_date(raw: str | None, today_local: date_cls) -> date_cls:
    if not raw:
        return today_local
    try:
        return date_cls.fromisoformat(raw)
    except ValueError:
        raise _fail(422, "date_invalid", "รูปแบบวันที่ต้องเป็น YYYY-MM-DD")


def _daily_payload(rows: list[HomeVerification], target: date_cls, now: datetime) -> dict:
    local_now = _local_now(now)
    return {
        "date": target.isoformat(),
        "server_date": local_now.date().isoformat(),
        "server_time": _iso_utc(now),
        "timezone": TIMEZONE_NAME,
        "verified": bool(rows),
        "verifications": [verification_out(row) for row in rows],
    }


@router.get("/me")
def my_verifications(
    response: Response,
    date: str | None = Query(None, description="วันตามเวลาไทย YYYY-MM-DD (ไม่ส่ง = วันนี้)"),
    emp: Employee = Depends(get_current_employee),
    db: Session = Depends(get_db),
):
    """ผลรายวันของตัวเอง พร้อมวันปัจจุบันของ server (อย่าเชื่อวันจากเครื่องผู้ใช้)"""
    response.headers["Cache-Control"] = "no-store"
    now = datetime.utcnow()
    target = _resolve_date(date, _local_now(now).date())
    rows = (
        db.query(HomeVerification)
        .filter_by(employee_id=emp.id, local_date=target)
        .order_by(HomeVerification.verified_at.desc())
        .all()
    )
    return _daily_payload(rows, target, now)


@router.get("/employee/{employee_id}")
def employee_verifications(
    employee_id: int,
    response: Response,
    date: str | None = Query(None, description="วันตามเวลาไทย YYYY-MM-DD (ไม่ส่ง = วันนี้)"),
    _: Employee = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """หัวหน้าดูผลของพนักงานรายคน — สิทธิ์เดียวกับรายงานเดิม (ต้องเป็นหัวหน้า)"""
    response.headers["Cache-Control"] = "no-store"
    if db.get(Employee, employee_id) is None:
        raise _fail(404, "employee_not_found", "ไม่พบพนักงานคนนี้")
    now = datetime.utcnow()
    target = _resolve_date(date, _local_now(now).date())
    rows = (
        db.query(HomeVerification)
        .filter_by(employee_id=employee_id, local_date=target)
        .order_by(HomeVerification.verified_at.desc())
        .all()
    )
    payload = _daily_payload(rows, target, now)
    payload["employee_id"] = employee_id
    return payload
