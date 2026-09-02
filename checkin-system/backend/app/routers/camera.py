"""ควบคุมกล้องวงจรปิด ONVIF ผ่าน API

กล้องเป็นอุปกรณ์ IP ในวง LAN ดังนั้น "เซิร์ฟเวอร์" ต้องอยู่วงเดียวกับกล้อง
แอป/เว็บคุยกับเซิร์ฟเวอร์ตัวนี้ แล้วเซิร์ฟเวอร์เป็นคนคุยกับกล้องอีกที

ทุก endpoint กันไว้ด้วย require_manager — พนักงานทั่วไปสั่งกล้องไม่ได้
"""

import threading
import time

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse

from camera_audio import AudioStream, find_ffmpeg
from camera_onvif import OnvifError, OnvifPtz

from ..config import settings
from ..models import Employee
from ..schemas import CameraPtzIn, CameraPtzOut, CameraStatusOut
from ..security import require_manager

router = APIRouter(prefix="/camera", tags=["camera"])

# กล้องตัวเดียวใช้ร่วมกันทั้งระบบ — ต่อครั้งเดียวแล้วใช้ซ้ำ
# ไม่งั้นทุกครั้งที่กดปุ่มจะต้องคุย SOAP ถาม profile ใหม่ ซึ่งช้าโดยไม่จำเป็น
_client: OnvifPtz | None = None
_client_lock = threading.Lock()

# กล้องรับคำสั่งได้ทีละอัน ถ้าหัวหน้าสองคนกดพร้อมกันจะได้ไม่ตีกัน
_command_lock = threading.Lock()


class SnapshotCache:
    """ภาพนิ่งล่าสุดที่ทุกคนใช้ร่วมกัน

    หัวใจของความนิ่งอยู่ตรงนี้ ก่อนหน้านี้ทุกคำขอยิงเข้ากล้องตรงๆ ซึ่งพังสองทาง:

      * กล้องตัวนี้รับคนดึงภาพพร้อมกันหลายรายไม่ไหว หัวหน้าเปิดสองเครื่อง =
        ยิงวินาทีละ 2 ครั้ง กล้องเริ่มตอบช้า แล้วหลุดเป็นช่วงๆ
      * คำขอที่รอกล้องจะจองเธรดของ FastAPI ไว้ (endpoint แบบ sync รันใน
        threadpool ที่แชร์กันทั้งแอป) กล้องช้าทีเดียวลากทั้งระบบช้าตาม

    ตัวนี้แก้ด้วยสามอย่าง: ภาพที่เพิ่งดึงใช้ซ้ำได้ระยะสั้นๆ, ดึงจากกล้อง
    ทีละรายเท่านั้น (คนที่เหลือรับภาพล่าสุดไปก่อน ไม่ต้องยืนรอ), และภาพหลุด
    ชั่วคราวยังส่งภาพล่าสุดที่ยังไม่เก่าเกินไปแทนการตอบ error
    """

    def __init__(self) -> None:
        self._fetch_lock = threading.Lock()
        self._state_lock = threading.Lock()
        self._image: bytes | None = None
        self._at: float = 0.0
        self._failures: int = 0

    def _cached(self, max_age: float) -> tuple[bytes, float] | None:
        with self._state_lock:
            if self._image is None:
                return None
            age = time.monotonic() - self._at
            return (self._image, age) if age <= max_age else None

    def _store(self, image: bytes) -> None:
        with self._state_lock:
            self._image = image
            self._at = time.monotonic()
            self._failures = 0

    def _should_reconnect(self) -> bool:
        """นับความล้มเหลว แล้วบอกว่าถึงคราวต่อกล้องใหม่หรือยัง

        ตัวนับถูกล้างทุกครั้งที่สั่งต่อใหม่ ไม่งั้นพอพลาดครบเพดานครั้งแรกแล้ว
        ทุกครั้งถัดไปจะเข้าเงื่อนไข ">= เพดาน" ตลอด กลายเป็นรีเซ็ตกล้องรัวๆ
        ซึ่งคือพายุ reconnect แบบเดียวกับที่ตั้งใจจะเลี่ยงตั้งแต่แรก
        """
        with self._state_lock:
            self._failures += 1
            if self._failures < settings.camera_reconnect_after_failures:
                return False
            self._failures = 0
            return True

    def get(self, camera: OnvifPtz) -> tuple[bytes, float]:
        """คืน (ภาพ, อายุของภาพเป็นวินาที) — โยน OnvifError เมื่อไม่มีภาพให้ส่งจริงๆ"""
        fresh = settings.camera_snapshot_cache_ms / 1000
        stale = settings.camera_snapshot_stale_ms / 1000

        cached = self._cached(fresh)
        if cached is not None:
            return cached

        # กล้องกำลังหมุนอยู่ ให้กล้องได้ทำทีละอย่าง — ระหว่างนี้ส่งภาพเดิมไปก่อน
        if _command_lock.locked():
            cached = self._cached(stale)
            if cached is not None:
                return cached

        # มีคนกำลังดึงจากกล้องอยู่แล้ว: รับภาพล่าสุดไปก่อนดีกว่าจองเธรดยืนรอ
        if not self._fetch_lock.acquire(blocking=False):
            cached = self._cached(stale)
            if cached is not None:
                return cached
            self._fetch_lock.acquire()

        try:
            # ระหว่างรอคิว คนข้างหน้าอาจดึงภาพใหม่มาให้แล้ว
            cached = self._cached(fresh)
            if cached is not None:
                return cached

            try:
                image = camera.fetch_snapshot(
                    timeout=settings.camera_snapshot_timeout_seconds
                )
            except OnvifError:
                # ต่อกล้องใหม่ต่อเมื่อพลาดติดกันหลายครั้ง — พลาดครั้งเดียวแล้ว
                # รีเซ็ตทันทีทำให้รอบถัดไปต้องคุย SOAP ใหม่ 4 ครั้งก่อนได้ภาพ
                # ยิ่งช้าก็ยิ่งพลาด กลายเป็นวนไม่จบ (นี่คือต้นเหตุที่ภาพดับยาว)
                if self._should_reconnect():
                    reset_camera()
                cached = self._cached(stale)
                if cached is not None:
                    return cached
                raise

            self._store(image)
            return image, 0.0
        finally:
            self._fetch_lock.release()


_snapshots = SnapshotCache()


def _require_enabled() -> None:
    if not settings.camera_ptz_enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ระบบกล้องถูกปิดไว้ที่เซิร์ฟเวอร์",
        )


def get_camera() -> OnvifPtz:
    """คืน client ที่ต่อกล้องไว้แล้ว — สร้างใหม่เฉพาะครั้งแรก"""
    global _client

    with _client_lock:
        if _client is None:
            _client = OnvifPtz(
                host=settings.camera_ptz_host,
                port=settings.camera_ptz_port,
                username=settings.camera_ptz_username or None,
                password=settings.camera_ptz_password,
                timeout=settings.camera_timeout_seconds,
                snapshot_timeout=settings.camera_snapshot_timeout_seconds,
            )
        return _client


def reset_camera() -> None:
    """ทิ้ง client ที่ค้างอยู่ ครั้งหน้าจะต่อใหม่

    ใช้เมื่อกล้องรีสตาร์ต/เปลี่ยน IP แล้ว token เดิมใช้ไม่ได้
    ภาพที่ค้างอยู่ใน cache ไม่ต้องทิ้ง — ยังเป็นภาพจากกล้องตัวเดิมอยู่ดี
    และเป็นสิ่งเดียวที่แอปมีให้ดูระหว่างที่กำลังต่อใหม่
    """
    global _client

    with _client_lock:
        _client = None


@router.get("/status", response_model=CameraStatusOut)
def camera_status(_: Employee = Depends(require_manager)):
    """เช็คว่าเซิร์ฟเวอร์คุยกับกล้องได้ไหม — แอปเรียกตอนเปิดหน้ากล้อง"""
    if not settings.camera_ptz_enabled:
        return CameraStatusOut(
            enabled=False,
            reachable=False,
            host=settings.camera_ptz_host,
            message="ระบบกล้องถูกปิดไว้ที่เซิร์ฟเวอร์",
        )

    camera = get_camera()
    try:
        camera.ensure_connected()
        info = camera.device_information()
    except OnvifError as exc:
        reset_camera()
        return CameraStatusOut(
            enabled=True,
            reachable=False,
            host=settings.camera_ptz_host,
            message=f"เชื่อมต่อกล้องไม่ได้: {exc}",
        )

    return CameraStatusOut(
        enabled=True,
        reachable=True,
        host=settings.camera_ptz_host,
        message="พร้อมใช้งาน",
        model=info.get("Model") or None,
        firmware=info.get("FirmwareVersion") or None,
        home_supported=camera.home_supported,
        audio_supported=(
            settings.camera_audio_enabled
            and find_ffmpeg(settings.ffmpeg_path or None) is not None
        ),
        # พูดกลับออกลำโพงกล้องยังทำไม่ได้ — ไม่ใช่เพราะกล้องไม่มีลำโพง
        #
        # ตรวจกับกล้องจริงแล้ว (cloudCam fw 43.4.0.0) กล้อง "มี" ลำโพง:
        #   GetCapabilities        -> AudioOutputs = 1
        #   GetAudioOutputConfigs  -> token AudioOutputToken, G711, OutputLevel 10
        #                             SendPrimacy = .../HalfDuplex/Auto (คุยสองทาง)
        #
        # แต่เฟิร์มแวร์ไม่เปิด "ช่องส่งเสียงเข้า" ให้เลยสักทาง:
        #   RTSP OPTIONS           -> DESCRIBE, PLAY, SETUP, TEARDOWN, SET_PARAMETER
        #                             (ไม่มี ANNOUNCE/RECORD)
        #   DESCRIBE + Require: www.onvif.org/ver20/backchannel
        #                          -> ได้ SDP เดิม ไม่มี track a=sendonly
        #                             ลองครบทุกเส้นทาง (/H265, /, /onvif1, ...)
        #   พอร์ตที่เปิด            -> มีแค่ 80 กับ 554 ไม่มีพอร์ตโปรโตคอลผู้ผลิต
        #
        # แปลว่าถ้าอยากได้ปุ่มกดพูด ต้องแก้ที่ตัวกล้อง (เปิดใน setting ของกล้อง
        # หรืออัปเฟิร์มแวร์ให้รองรับ backchannel) ไม่ใช่แก้ที่แอป —
        # เปลี่ยนค่านี้เป็น True ได้ทันทีที่ DESCRIBE ตอบ track a=sendonly มา
        talkback_supported=False,
    )


@router.post("/ptz", response_model=CameraPtzOut)
def move_camera(
    payload: CameraPtzIn,
    _: Employee = Depends(require_manager),
):
    """สั่งกล้องหมุน แล้วเซิร์ฟเวอร์สั่งหยุดให้เองเมื่อครบเวลา

    ทำแบบนี้แทนที่จะให้ client ส่ง stop ตามมาทีหลัง เพราะถ้ามือถือเน็ตหลุด
    ระหว่างกดค้าง คำสั่ง stop จะไม่ถึงกล้อง แล้วกล้องจะหมุนค้างไปเรื่อยๆ
    """
    _require_enabled()

    duration_ms = payload.duration_ms or settings.camera_ptz_duration_ms
    duration_ms = min(duration_ms, settings.camera_ptz_max_duration_ms)

    camera = get_camera()
    try:
        with _command_lock:
            camera.move_pulse(
                payload.action,
                duration=duration_ms / 1000,
                speed=settings.camera_ptz_speed,
                zoom_speed=settings.camera_ptz_zoom_speed,
                invert_pan=settings.camera_ptz_invert_pan,
                invert_tilt=settings.camera_ptz_invert_tilt,
            )
    except OnvifError as exc:
        reset_camera()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"สั่งกล้องไม่สำเร็จ: {exc}",
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"คำสั่งกล้องไม่ถูกต้อง: {exc}",
        )

    return CameraPtzOut(ok=True, action=payload.action, message="สั่งกล้องแล้ว")


@router.post("/ptz/stop", response_model=CameraPtzOut)
def stop_camera(_: Employee = Depends(require_manager)):
    """สั่งหยุดทันที — ปุ่มฉุกเฉินเผื่อกล้องค้างหมุน"""
    _require_enabled()

    camera = get_camera()
    try:
        with _command_lock:
            camera.stop()
    except OnvifError as exc:
        reset_camera()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"สั่งหยุดกล้องไม่สำเร็จ: {exc}",
        )

    return CameraPtzOut(ok=True, action="stop", message="สั่งหยุดแล้ว")


@router.get(
    "/snapshot",
    responses={200: {"content": {"image/jpeg": {}}}},
    response_class=Response,
)
def camera_snapshot(_: Employee = Depends(require_manager)):
    """ภาพนิ่งล่าสุดจากกล้อง

    แอปเรียกซ้ำเป็นระยะเพื่อทำเป็นภาพสด — เบากว่าการต่อ RTSP มาก และไม่ต้อง
    เปิดพอร์ตกล้องออกอินเทอร์เน็ต เพราะภาพวิ่งผ่านเซิร์ฟเวอร์ที่ล็อกอินแล้ว
    """
    _require_enabled()

    camera = get_camera()
    try:
        image, age = _snapshots.get(camera)
    except OnvifError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"ดึงภาพจากกล้องไม่สำเร็จ: {exc}",
        )

    return Response(
        content=image,
        media_type="image/jpeg",
        headers={
            # ภาพสด — ห้ามให้ตัวกลางไหนแคชไว้ ไม่งั้นแอปจะได้ภาพเก่าเดิมซ้ำๆ
            # (การใช้ภาพซ้ำทำที่นี่ที่เดียว ซึ่งรู้ว่าภาพเก่าไปกี่มิลลิวินาที)
            "Cache-Control": "no-store",
            # อายุของภาพ — แอปเอาไปบอกผู้ใช้ได้ว่ากำลังดูภาพสดหรือภาพค้าง
            "X-Snapshot-Age-Ms": str(int(age * 1000)),
        },
    )


@router.get(
    "/audio",
    responses={200: {"content": {"audio/aac": {}}}},
    response_class=StreamingResponse,
)
async def camera_audio(
    request: Request,
    _: Employee = Depends(require_manager),
):
    """ฟังเสียงจากไมค์ของกล้องแบบสด

    เป็นเสียงขาเข้าอย่างเดียว — กล้องรุ่นนี้ไม่มีลำโพงและไม่เปิด RTSP
    backchannel จึงพูดกลับออกกล้องไม่ได้

    เสียงเริ่มดังช้าประมาณ 6 วินาที เพราะต้องรอกล้อง setup RTSP ให้เสร็จก่อน
    ไม่ใช่เพราะฝั่งเซิร์ฟเวอร์ช้า
    """
    _require_enabled()

    if not settings.camera_audio_enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ระบบเสียงถูกปิดไว้ที่เซิร์ฟเวอร์",
        )

    if find_ffmpeg(settings.ffmpeg_path or None) is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="เซิร์ฟเวอร์นี้ยังไม่ได้ติดตั้ง ffmpeg จึงส่งเสียงไม่ได้",
        )

    stream = AudioStream(
        rtsp_url=settings.camera_rtsp_url,
        ffmpeg_path=settings.ffmpeg_path or None,
        bitrate=settings.camera_audio_bitrate,
    ).start()

    async def chunks():
        # ต้องเป็น async generator — ตัว sync generator ที่ StreamingResponse
        # รันใน threadpool จะไม่ถูก close() เมื่อแอปตัดการเชื่อมต่อ ทำให้
        # ffmpeg ค้างคาเครื่องและเปิด RTSP ค้างไว้กับกล้องไปเรื่อยๆ
        try:
            while True:
                if await request.is_disconnected():
                    break
                chunk = await run_in_threadpool(stream.read)
                if not chunk:
                    break
                yield chunk
        finally:
            stream.close()

    return StreamingResponse(
        chunks(),
        media_type="audio/aac",
        headers={"Cache-Control": "no-store"},
    )
