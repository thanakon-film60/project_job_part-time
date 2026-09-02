"""ตรวจว่าตัวแคชภาพนิ่งของกล้อง (SnapshotCache) ยังทำงานถูกต้อง

รันด้วย:
    venv\\Scripts\\python.exe camera_cache_check.py

ตัวนี้ไม่แตะกล้องจริงและไม่แตะฐานข้อมูล — ใช้กล้องปลอมล้วนๆ จึงรันได้ทุกเครื่อง
แม้ไม่ได้อยู่วงเดียวกับกล้อง (อยากทดสอบกับกล้องจริงให้ใช้ camera_probe.py)

ทำไมต้องมีไฟล์นี้: ความนิ่งของภาพในแอปขึ้นกับตรรกะไม่กี่บรรทัดใน SnapshotCache
ซึ่งเป็นเรื่องของ "จังหวะเวลา + หลายเธรด" ที่ดูจากโค้ดเปล่าๆ แล้วมองไม่ออกว่าพัง
เคยพลาดมาแล้วสองแบบ และทั้งสองแบบถูกดักไว้ในข้อ 4 กับข้อ 5 ข้างล่าง
"""

import importlib
import sys
import threading
import time
import types

import sqlalchemy.orm

# app.routers.camera ลากเอา app.database (ซึ่งต่อ PostgreSQL จริง) มาด้วย
# ตรงนี้ทดสอบแค่ตรรกะแคช จึงใส่ตัวหลอกแทน จะได้ไม่ต้องมีฐานข้อมูล
_fake_db = types.ModuleType("app.database")
_fake_db.Base = sqlalchemy.orm.declarative_base()
_fake_db.engine = None
_fake_db.SessionLocal = None
_fake_db.get_db = lambda: None
sys.modules.setdefault("app.database", _fake_db)

camera = importlib.import_module("app.routers.camera")

from camera_onvif import OnvifError  # noqa: E402  (ต้อง import หลังใส่ตัวหลอก)


CACHE_MS = 700
STALE_MS = 8000
RECONNECT_AFTER = 3


class FakeCamera:
    """กล้องปลอม — นับว่าถูกเรียกกี่ครั้ง และสั่งให้พังหรือให้ช้าได้"""

    def __init__(self):
        self.calls = 0
        self.fail = False
        self.delay = 0.0

    def fetch_snapshot(self, timeout=None):
        self.calls += 1
        if self.delay:
            time.sleep(self.delay)
        if self.fail:
            raise OnvifError("กล้องปลอมถูกสั่งให้พัง")
        return b"\xff\xd8" + bytes([self.calls % 251])


def _fresh():
    return camera.SnapshotCache(), FakeCamera()


def check_cache_reuses_recent_frame():
    """ยิงถี่ๆ ในช่วงอายุแคช = กล้องต้องโดนแค่ครั้งเดียว"""
    cache, cam = _fresh()
    for _ in range(20):
        cache.get(cam)
    assert cam.calls == 1, f"ควรยิงกล้องครั้งเดียว แต่ยิง {cam.calls} ครั้ง"
    return f"แอปยิง 20 ครั้ง -> กล้องโดน {cam.calls} ครั้ง"


def check_concurrent_viewers_share_one_fetch():
    """หัวหน้าหลายเครื่องดูพร้อมกัน = กล้องโดนครั้งเดียว และไม่มีใครยืนรอ

    ข้อนี้คือหัวใจ: ก่อนหน้านี้ทุกคำขอยิงเข้ากล้องตรงๆ แล้วจองเธรดของ FastAPI
    ไว้รอ กล้องช้าทีเดียวลากทั้งระบบช้าตาม
    """
    cache, cam = _fresh()
    cam.delay = 0.25
    results, errors = [], []

    def viewer():
        try:
            results.append(cache.get(cam))
        except Exception as exc:  # noqa: BLE001 - เก็บไว้รายงาน
            errors.append(exc)

    threads = [threading.Thread(target=viewer) for _ in range(8)]
    started = time.monotonic()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.monotonic() - started

    assert not errors, f"มีคำขอที่พลาด: {errors}"
    assert len(results) == 8, f"ได้ภาพกลับมา {len(results)} ราย ควรเป็น 8"
    assert cam.calls == 1, f"ควรยิงกล้องครั้งเดียว แต่ยิง {cam.calls} ครั้ง"
    return f"8 คนพร้อมกัน -> กล้องโดน {cam.calls} ครั้ง, ใช้เวลารวม {elapsed:.2f}s"


def check_serves_stale_frame_when_camera_hiccups():
    """กล้องสะดุด = ส่งภาพล่าสุดไปก่อน ไม่ใช่ตอบ error ให้แอปขึ้นเตือน"""
    cache, cam = _fresh()
    image, _ = cache.get(cam)

    cam.fail = True
    time.sleep(CACHE_MS / 1000 + 0.05)      # ให้เลยอายุภาพสด
    stale_image, age = cache.get(cam)

    assert stale_image == image, "ควรได้ภาพล่าสุดกลับมา"
    assert age > CACHE_MS / 1000, f"อายุภาพควรเกิน {CACHE_MS}ms แต่ได้ {age*1000:.0f}ms"
    return f"กล้องหลุด -> ยังได้ภาพเดิม อายุ {age*1000:.0f}ms"


def check_reconnect_is_throttled():
    """ต่อกล้องใหม่ทุกๆ N ครั้งที่พลาด ไม่ใช่ทุกครั้งหลังพลาดครบ N

    เคยพลาดตรงนี้: เช็ค ">= เพดาน" โดยไม่ล้างตัวนับ พอพลาดครบ 3 ครั้งแรกแล้ว
    ครั้งที่ 4, 5, 6... ก็เข้าเงื่อนไขตลอด กลายเป็นรีเซ็ตกล้องรัวๆ
    ซึ่งคือพายุ reconnect แบบเดียวกับที่ตั้งใจจะเลี่ยงตั้งแต่แรก
    """
    cache, cam = _fresh()
    cam.fail = True
    resets = []
    original = camera.reset_camera
    camera.reset_camera = lambda: resets.append(1)
    try:
        for _ in range(12):
            try:
                cache.get(cam)
            except OnvifError:
                pass
    finally:
        camera.reset_camera = original

    expected = 12 // RECONNECT_AFTER
    assert len(resets) == expected, (
        f"พลาด 12 ครั้ง เพดาน {RECONNECT_AFTER} -> ควรต่อใหม่ {expected} ครั้ง "
        f"แต่ได้ {len(resets)} ครั้ง"
    )
    return f"พลาด 12 ครั้งติด -> ต่อกล้องใหม่ {len(resets)} ครั้ง (ทุกๆ {RECONNECT_AFTER})"


def check_success_resets_failure_streak():
    """สำเร็จคั่นกลาง = เริ่มนับความล้มเหลวใหม่ ไม่สะสมข้ามช่วง"""
    cache, cam = _fresh()
    resets = []
    original = camera.reset_camera
    camera.reset_camera = lambda: resets.append(1)
    try:
        cam.fail = True
        for _ in range(RECONNECT_AFTER - 1):
            try:
                cache.get(cam)
            except OnvifError:
                pass

        cam.fail = False
        cache.get(cam)                       # สำเร็จ -> ตัวนับต้องถูกล้าง

        cam.fail = True
        for _ in range(RECONNECT_AFTER - 1):
            time.sleep(CACHE_MS / 1000 + 0.05)
            try:
                cache.get(cam)
            except OnvifError:
                pass
    finally:
        camera.reset_camera = original

    assert not resets, f"ไม่ควรต่อกล้องใหม่เลย แต่ต่อ {len(resets)} ครั้ง"
    return f"พลาด {RECONNECT_AFTER-1} -> สำเร็จ -> พลาด {RECONNECT_AFTER-1}: ไม่ต่อใหม่เลย"


def check_yields_camera_while_moving():
    """ระหว่างกล้องหมุน อย่าไปแย่งดึงภาพ — กล้องทำทีละอย่างได้ดีกว่า"""
    cache, cam = _fresh()
    cache.get(cam)
    before = cam.calls

    time.sleep(CACHE_MS / 1000 + 0.05)
    with camera._command_lock:
        cache.get(cam)

    assert cam.calls == before, "ระหว่างกล้องหมุนไม่ควรยิงขอภาพเพิ่ม"
    return "ระหว่างกล้องหมุน -> ไม่ยิงขอภาพซ้อน"


CHECKS = [
    ("ใช้ภาพซ้ำในช่วงอายุแคช", check_cache_reuses_recent_frame),
    ("หลายคนดูพร้อมกันแชร์ภาพเดียว", check_concurrent_viewers_share_one_fetch),
    ("กล้องสะดุดแล้วยังส่งภาพเดิม", check_serves_stale_frame_when_camera_hiccups),
    ("ต่อกล้องใหม่แบบมีจังหวะ", check_reconnect_is_throttled),
    ("สำเร็จคั่นกลางแล้วเริ่มนับใหม่", check_success_resets_failure_streak),
    ("ยอมให้กล้องหมุนก่อน", check_yields_camera_while_moving),
]


def main():
    settings = camera.settings
    settings.camera_snapshot_cache_ms = CACHE_MS
    settings.camera_snapshot_stale_ms = STALE_MS
    settings.camera_snapshot_timeout_seconds = 6.0
    settings.camera_reconnect_after_failures = RECONNECT_AFTER

    failures = 0
    for index, (label, check) in enumerate(CHECKS, start=1):
        try:
            detail = check()
        except AssertionError as exc:
            failures += 1
            print(f"{index}. {label}: ไม่ผ่าน")
            print(f"     {exc}")
        else:
            print(f"{index}. {label}: ผ่าน")
            print(f"     {detail}")

    print()
    if failures:
        print(f"ไม่ผ่าน {failures} ข้อ จากทั้งหมด {len(CHECKS)} ข้อ")
        return 1
    print(f"ผ่านครบทั้ง {len(CHECKS)} ข้อ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
