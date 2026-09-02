"""ตรวจตรรกะเรื่องเสียงของกล้อง — ตัวตรวจ backchannel และการจำผล

รันด้วย:
    venv\\Scripts\\python.exe camera_audio_check.py

ไม่ต้องมีกล้องและไม่ต้องมี ffmpeg — ทดสอบตรรกะล้วน ๆ
(อยากทดสอบกับกล้องจริงให้ใช้ camera_probe.py)

ทำไมต้องมีไฟล์นี้: `talkback_supported` เคยเป็นค่าคงที่ False ซึ่งถูกกับกล้อง
ตัวที่ใช้อยู่ แต่จะกลายเป็นคำตอบผิดแบบเงียบ ๆ ทันทีที่เปลี่ยนกล้องหรืออัปเฟิร์มแวร์
ตอนนี้เปลี่ยนเป็นไปถามกล้องจริง ตรรกะการอ่านคำตอบจึงต้องมีตัวดักไว้
"""

import sys
import threading
import time

import camera_audio
from camera_audio import (
    AudioHub,
    _split_rtsp_url,
    backchannel_supported,
    sdp_has_backchannel,
)


CRLF = "\r\n"


def sdp(*lines):
    return CRLF.join(lines) + CRLF


def check_url_parsing():
    """แยก RTSP URL ได้ถูกต้องทุกรูปแบบที่ตั้งค่าได้จริง"""
    cases = {
        "rtsp://192.168.1.101:554": ("192.168.1.101", 554, "/"),
        "rtsp://192.168.1.101": ("192.168.1.101", 554, "/"),
        "rtsp://192.168.1.101:554/H265": ("192.168.1.101", 554, "/H265"),
        "rtsp://10.0.0.5:8554/live/ch0": ("10.0.0.5", 8554, "/live/ch0"),
        # กล้องที่ตั้งรหัสผ่าน — ต้องตัด user:pass@ ออกก่อนต่อ socket
        "rtsp://boss:secret@10.0.0.5/H265": ("10.0.0.5", 554, "/H265"),
    }
    for url, expected in cases.items():
        got = _split_rtsp_url(url)
        assert got == expected, f"{url} -> {got} (ควรเป็น {expected})"
    return f"แยกถูกครบ {len(cases)} รูปแบบ"


def check_sdp_without_backchannel():
    """กล้องที่ส่งเสียงออกอย่างเดียว = ยังพูดกลับไม่ได้

    นี่คือ SDP จริงจากกล้อง cloudCam fw 43.4.0.0 ที่ใช้อยู่
    """
    text = sdp(
        "v=0",
        "a=control:*",
        "m=video 0 RTP/AVP 96",
        "a=rtpmap:96 H265/90000",
        "a=control:trackID=1",
        "m=audio 0 RTP/AVP 8",
        "a=rtpmap:8 PCMA/8000/1",
        "a=control:trackID=2",
    )
    assert sdp_has_backchannel(text) is False
    return "SDP ของกล้องตัวปัจจุบัน -> พูดกลับไม่ได้ (ถูกต้อง)"


def check_sdp_with_backchannel():
    """กล้องที่เปิด backchannel จะมีช่องเสียงอีกช่องที่ทำเครื่องหมาย sendonly"""
    text = sdp(
        "v=0",
        "m=video 0 RTP/AVP 96",
        "a=control:trackID=1",
        "m=audio 0 RTP/AVP 8",
        "a=rtpmap:8 PCMA/8000/1",
        "a=control:trackID=2",
        "m=audio 0 RTP/AVP 0",
        "a=rtpmap:0 PCMU/8000",
        "a=control:trackID=3",
        "a=sendonly",
    )
    assert sdp_has_backchannel(text) is True
    return "SDP ที่มี track a=sendonly -> พูดกลับได้"


def check_sendonly_on_video_is_not_backchannel():
    """a=sendonly ใต้ช่องวิดีโอไม่เกี่ยวกับการพูดกลับ

    ข้อนี้กันการอ่านแบบ "หา a=sendonly ทั้งไฟล์" ซึ่งจะตอบผิดเป็น "พูดได้"
    ให้กับกล้องที่แค่ประกาศว่าวิดีโอเป็นขาส่งทางเดียว
    """
    text = sdp(
        "v=0",
        "m=video 0 RTP/AVP 96",
        "a=sendonly",
        "m=audio 0 RTP/AVP 8",
        "a=rtpmap:8 PCMA/8000/1",
    )
    assert sdp_has_backchannel(text) is False
    return "a=sendonly ใต้ video -> ไม่นับว่าพูดกลับได้ (ถูกต้อง)"


def _stub_probe(result):
    """แทนที่ probe_backchannel ชั่วคราวด้วยผลที่กำหนดเอง"""
    calls = []

    def fake(rtsp_url, timeout=6.0):
        calls.append(rtsp_url)
        return result

    return fake, calls


def _with_stub(result, body):
    original = camera_audio.probe_backchannel
    fake, calls = _stub_probe(result)
    camera_audio.probe_backchannel = fake
    camera_audio._backchannel_cache.clear()
    try:
        return body(calls)
    finally:
        camera_audio.probe_backchannel = original
        camera_audio._backchannel_cache.clear()


def check_conclusive_answer_is_cached():
    """คำตอบที่กล้องยืนยันแล้ว ไม่ต้องไปถามซ้ำทุกครั้งที่แอปเปิดแท็บ"""
    def body(calls):
        for _ in range(5):
            backchannel_supported("rtsp://cam/1")
        assert len(calls) == 1, f"ควรถามกล้องครั้งเดียว แต่ถาม {len(calls)} ครั้ง"
        return f"ถาม 5 ครั้ง -> คุยกับกล้องจริง {len(calls)} ครั้ง"

    return _with_stub((False, "ไม่พบ a=sendonly", True), body)


def check_unreachable_is_not_cached():
    """ต่อกล้องไม่ติดชั่วคราว ต้องไม่ถูกจำว่า "พูดไม่ได้" ค้างไว้

    ถ้าจำผลนี้ กล้องสะดุดทีเดียวแล้วปุ่มกดพูดจะหายไป 5 นาทีโดยไม่มีเหตุผล
    ทั้งที่กล้องอาจรองรับอยู่
    """
    def body(calls):
        for _ in range(4):
            backchannel_supported("rtsp://cam/2")
        assert len(calls) == 4, f"ควรลองใหม่ทุกครั้ง แต่ลอง {len(calls)} ครั้ง"
        assert not camera_audio._backchannel_cache, "ไม่ควรจำผลที่สรุปไม่ได้"
        return f"ถาม 4 ครั้ง -> ลองต่อกล้องใหม่ครบ {len(calls)} ครั้ง"

    return _with_stub((False, "ต่อ RTSP ไม่ได้: timed out", False), body)


def check_supported_camera_reports_true():
    """กล้องที่รองรับต้องได้ True ส่งต่อไปให้แอปเปิดปุ่ม"""
    def body(_calls):
        supported, detail = backchannel_supported("rtsp://cam/3")
        assert supported is True, "ควรตอบว่าพูดกลับได้"
        return f"กล้องที่รองรับ -> True ({detail})"

    return _with_stub((True, "พบ a=sendonly", True), body)


class FakeStream:
    """สตรีมปลอมที่ป้อนเสียงเรื่อย ๆ และบอกได้ว่าถูกปิดหรือยัง"""

    def __init__(self):
        self.closed = threading.Event()

    def read(self):
        if self.closed.is_set():
            return b""
        time.sleep(0.05)
        return bytes([0xFF, 0xF1]) + b"audio"   # ลายเซ็นหัวเฟรม ADTS

    def close(self):
        self.closed.set()


def check_hub_shares_one_stream():
    """ผู้ฟังหลายคน = ffmpeg ตัวเดียว ไม่ใช่คนละตัว

    กล้องรับผู้เชื่อมต่อได้จำกัด หัวหน้าสองคนเปิดฟังพร้อมกันไม่ควรกินโควตาสองที่
    """
    created = []
    hub = AudioHub(make_stream=lambda: created.append(FakeStream()) or created[-1],
                   max_seconds=30)
    try:
        listeners = [hub.subscribe() for _ in range(4)]
        time.sleep(0.4)
        assert len(created) == 1, f"ควรสร้างสตรีมเดียว แต่สร้าง {len(created)}"

        got = [len(hub.read(l, timeout=2)) for l in listeners]
        assert all(n > 0 for n in got), f"บางคนไม่ได้เสียง: {got}"
        for l in listeners:
            hub.unsubscribe(l)
    finally:
        hub.close()
    return f"ผู้ฟัง 4 คน -> สตรีม {len(created)} ตัว และได้เสียงครบทุกคน"


def check_hub_stops_when_everyone_leaves():
    """ไม่มีคนฟังแล้ว ffmpeg ต้องปิดตัวเอง ไม่ค้างจับกล้องไว้"""
    created = []
    hub = AudioHub(make_stream=lambda: created.append(FakeStream()) or created[-1],
                   max_seconds=30)
    try:
        listener = hub.subscribe()
        hub.read(listener, timeout=2)
        hub.unsubscribe(listener)

        deadline = time.monotonic() + camera_audio.IDLE_GRACE_SECONDS + 5
        while time.monotonic() < deadline:
            if created[0].closed.is_set():
                break
            time.sleep(0.2)
        assert created[0].closed.is_set(), "สตรีมไม่ยอมปิดเมื่อไม่มีคนฟัง"
    finally:
        hub.close()
    return "ผู้ฟังคนสุดท้ายออก -> สตรีมปิดเอง"


def check_hub_enforces_max_lifetime():
    """แอปไม่ยอมปิดสาย -> เซิร์ฟเวอร์ต้องตัดเองเมื่อครบเพดานอายุ

    นี่คือกันเคสที่เจอจริง: ผู้ใช้กดหยุดแล้ว แต่ตัวเล่นเสียงบน Android ยังคาสาย
    ไว้กับเซิร์ฟเวอร์ (วัดได้เกิน 77 วินาที) ถ้าไม่มีเพดานนี้ ffmpeg จะจับ RTSP
    ของกล้องค้างไว้ข้ามคืน
    """
    created = []
    hub = AudioHub(make_stream=lambda: created.append(FakeStream()) or created[-1],
                   max_seconds=1.0)
    try:
        listener = hub.subscribe()          # ผู้ฟังที่ "ไม่ยอมจากไป"
        started = time.monotonic()
        while True:
            if not hub.read(listener, timeout=5):
                break
        elapsed = time.monotonic() - started
        assert elapsed < 5, f"ควรถูกตัดที่ราว 1 วินาที แต่ใช้ {elapsed:.1f}"
        assert created[0].closed.is_set(), "ครบเพดานแล้วสตรีมต้องถูกปิด"
    finally:
        hub.close()
    return f"ผู้ฟังไม่ยอมตัดสาย -> เซิร์ฟเวอร์ตัดเองที่ {elapsed:.1f} วินาที"


CHECKS = [
    ("แยก RTSP URL", check_url_parsing),
    ("กล้องที่พูดกลับไม่ได้", check_sdp_without_backchannel),
    ("กล้องที่พูดกลับได้", check_sdp_with_backchannel),
    ("ไม่สับสนกับ sendonly ของวิดีโอ", check_sendonly_on_video_is_not_backchannel),
    ("จำคำตอบที่ยืนยันแล้ว", check_conclusive_answer_is_cached),
    ("ไม่จำตอนต่อกล้องไม่ติด", check_unreachable_is_not_cached),
    ("กล้องที่รองรับตอบ True", check_supported_camera_reports_true),
    ("หลายคนฟังใช้สตรีมเดียว", check_hub_shares_one_stream),
    ("ไม่มีคนฟังแล้วปิดเอง", check_hub_stops_when_everyone_leaves),
    ("เพดานอายุของสตรีม", check_hub_enforces_max_lifetime),
]


def main():
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
