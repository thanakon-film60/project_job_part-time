"""ดึงเสียงจากไมค์ของกล้อง RTSP ออกมาเป็นสตรีม AAC ให้แอปเล่นได้

กล้องส่งเสียงมาเป็น G.711 (PCMA 8kHz) ซึ่งเล่นตรงๆ ผ่าน HTTP ไม่ได้
จึงให้ ffmpeg แปลงเป็น AAC/ADTS ที่ ExoPlayer บน Android เล่นสตรีมสดได้เลย

ตอนนี้เป็นเสียง "ขาเข้า" อย่างเดียว เพราะกล้องที่ใช้อยู่ไม่เปิดช่องรับเสียง
ดู probe_backchannel ท้ายไฟล์ — ตัวนั้นไปถามกล้องจริงว่ารับเสียงเข้าได้ไหม
แทนการเขียนคำตอบตายตัวไว้ ซึ่งจะกลายเป็นคำตอบผิดทันทีที่เปลี่ยนกล้อง
"""

import os
import queue
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


DEFAULT_FFMPEG_PATH = r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"

# อ่านทีละก้อนเท่านี้ — เล็กพอให้เสียงเริ่มดังเร็ว ไม่ต้องรอบัฟเฟอร์เต็ม
CHUNK_SIZE = 4096


def find_ffmpeg(explicit_path=None):
    candidates = []
    if explicit_path:
        candidates.append(explicit_path)
    which_path = shutil.which("ffmpeg.exe") or shutil.which("ffmpeg")
    if which_path:
        candidates.append(which_path)
    candidates.append(DEFAULT_FFMPEG_PATH)

    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(Path(candidate))
    return None


def build_command(ffmpeg_path, rtsp_url, bitrate="32k", sample_rate=16000):
    return [
        ffmpeg_path,
        "-hide_banner",
        "-loglevel", "error",
        "-rtsp_transport", "tcp",
        # เสียงเป็น G.711 ที่รู้รูปแบบแน่นอนอยู่แล้ว ไม่ต้องดมนาน
        # (ห้ามใส่ -allowed_media_types audio — กล้องรุ่นนี้ต้องเปิด track
        #  วิดีโอด้วย ไม่งั้นไม่ส่งอะไรมาเลย ทดสอบแล้วได้ 0 ไบต์)
        "-probesize", "32768",
        "-analyzeduration", "0",
        "-fflags", "nobuffer",
        "-i", rtsp_url,
        "-vn",                       # ทิ้งภาพ เอาแต่เสียง
        "-c:a", "aac",
        "-b:a", bitrate,
        "-ar", str(sample_rate),
        "-ac", "1",
        "-f", "adts",                # ADTS = สตรีมสดได้ ไม่ต้องมี header ตอนจบ
        "pipe:1",
    ]


def start_process(command):
    kwargs = {}
    if sys.platform.startswith("win"):
        kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
    else:
        # แยกกลุ่ม process ไว้ตั้งแต่ต้น เพื่อให้ stop_process ส่งสัญญาณ
        # ถึงลูกหลานได้ครบทีเดียว
        kwargs["start_new_session"] = True

    return subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
        **kwargs,
    )


def _drain(pipe):
    """อ่าน stderr ทิ้งในเธรดแยก

    ถ้าปล่อยไว้ไม่อ่าน บัฟเฟอร์ของ pipe จะเต็มแล้ว ffmpeg จะค้างเขียนไม่ไป
    ทำให้เสียงหยุดกลางคัน
    """
    try:
        for _ in iter(pipe.readline, b""):
            pass
    except (OSError, ValueError):
        pass


def _kill_tree_windows(pid):
    """ฆ่า process พร้อมลูกหลานทั้งหมดบน Windows

    ต้องฆ่าทั้งต้นไม้ ไม่ใช่แค่ตัวที่ Popen ถืออยู่ — ffmpeg ที่ติดตั้งด้วย
    chocolatey เป็น "ตัวนำ" (shim) ที่ไปเรียก ffmpeg ตัวจริงเป็นลูกอีกที
    terminate() จะฆ่าได้แค่ตัวนำ ส่วนตัวจริงจะรอดแล้วเปิด RTSP ค้างไว้กับกล้อง
    ตลอดไป

    เรื่องนี้ไม่ใช่แค่เปลืองหน่วยความจำ — กล้องรับผู้เชื่อมต่อได้จำกัด ตัวที่
    รั่วสะสมทำให้กล้องช้าลงเรื่อย ๆ จนภาพนิ่งกับคำสั่งหมุนพลอยหลุดไปด้วย
    (เคยเจอค้างถึง 13 ตัวจากการกดฟังเสียงครั้งเดียว)
    """
    subprocess.run(
        ["taskkill", "/PID", str(pid), "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=subprocess.CREATE_NO_WINDOW,
        check=False,
    )


def stop_process(process):
    """ปิด ffmpeg ให้สนิท รวมถึงลูกหลานที่มันเปิดไว้"""
    if process.poll() is not None:
        return

    if sys.platform.startswith("win"):
        _kill_tree_windows(process.pid)
    else:
        # บน POSIX ตั้งกลุ่ม process ไว้ตอนเปิด (ดู start_process) จึงส่ง
        # สัญญาณทีเดียวถึงทั้งกลุ่มได้
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except (OSError, AttributeError):
            process.terminate()

    try:
        process.wait(timeout=3)
        return
    except subprocess.TimeoutExpired:
        pass

    process.kill()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass


class AudioStream:
    """ffmpeg หนึ่งตัวที่แปลงเสียงกล้องให้ผู้ฟังหนึ่งราย

    แยกเป็นคลาสแทนที่จะเป็น generator เฉยๆ เพราะฝั่ง router ต้องถือ handle
    ไว้ปิดเองได้ ตอนแอปตัดการเชื่อมต่อกลางคัน — ถ้าใช้ sync generator ใน
    StreamingResponse ตัว finally จะไม่ถูกเรียกเมื่อ client หลุด แล้ว ffmpeg
    จะค้างคาเครื่องพร้อมกับเปิด RTSP ค้างไว้กับกล้องด้วย
    """

    def __init__(self, rtsp_url, ffmpeg_path=None, bitrate="32k", sample_rate=16000):
        resolved = find_ffmpeg(ffmpeg_path)
        if resolved is None:
            raise FileNotFoundError("ffmpeg was not found on this server")

        self.command = build_command(resolved, rtsp_url, bitrate, sample_rate)
        self.process = None

    def start(self):
        self.process = start_process(self.command)
        threading.Thread(
            target=_drain, args=(self.process.stderr,), daemon=True
        ).start()
        return self

    def read(self):
        """อ่านก้อนถัดไป (บล็อก) — คืน b"" เมื่อสตรีมจบหรือถูกปิด"""
        if self.process is None or self.process.stdout is None:
            return b""
        try:
            return self.process.stdout.read(CHUNK_SIZE)
        except (OSError, ValueError):
            return b""

    def close(self):
        if self.process is not None:
            stop_process(self.process)
            self.process = None


def stream_audio(rtsp_url, ffmpeg_path=None, bitrate="32k", sample_rate=16000):
    """generator แบบง่ายสำหรับสคริปต์ทดสอบ — ปิด generator แล้ว ffmpeg ตายตาม

    ฝั่ง API ไม่ได้ใช้ตัวนี้ ใช้ AudioStream ตรงๆ เพราะต้องคุมการปิดเอง
    """
    stream = AudioStream(rtsp_url, ffmpeg_path, bitrate, sample_rate).start()
    try:
        while True:
            chunk = stream.read()
            if not chunk:
                break
            yield chunk
    finally:
        stream.close()


# ===================================================================
# ตรวจว่ากล้อง "รับเสียงเข้า" ได้ไหม (ONVIF backchannel)
#
# ก่อนหน้านี้ฝั่ง API ตอบ talkback_supported=False ตายตัว ซึ่งถูกกับกล้องตัวที่
# ใช้อยู่ แต่กลายเป็นคำตอบผิดทันทีที่เปลี่ยนกล้องหรืออัปเฟิร์มแวร์ แล้วไม่มีอะไร
# บอกให้รู้ ตัวนี้จึงไปถามกล้องจริงแทนการเดา
#
# วิธีของ ONVIF Profile T: ส่ง DESCRIBE พร้อมหัวข้อ Require แล้วดูว่า SDP ที่
# ตอบกลับมามีช่องเสียงที่ทำเครื่องหมาย a=sendonly หรือไม่ (sendonly = ฝั่ง
# เซิร์ฟเวอร์เป็นผู้รับ เราเป็นผู้ส่ง) ถ้ามี แปลว่าส่งเสียงเข้ากล้องได้
# ===================================================================

BACKCHANNEL_REQUIRE = "www.onvif.org/ver20/backchannel"

# ผลตรวจไม่เปลี่ยนระหว่างวัน (เปลี่ยนก็ต่อเมื่ออัปเฟิร์มแวร์/เปลี่ยนกล้อง)
# จำไว้สักพักจะได้ไม่ต้องเปิด TCP ไปหากล้องทุกครั้งที่แอปถามสถานะ
BACKCHANNEL_CACHE_SECONDS = 300

_backchannel_cache = {}
_backchannel_lock = threading.Lock()


def _split_rtsp_url(rtsp_url):
    """แยก rtsp://host:port/path ออกเป็นชิ้น ๆ (คืนพอร์ต 554 ถ้าไม่ได้ระบุ)"""
    rest = rtsp_url.split("://", 1)[-1]
    authority, _, path = rest.partition("/")
    # ตัด user:pass@ ออกถ้ามี
    if "@" in authority:
        authority = authority.rsplit("@", 1)[-1]
    host, _, port = authority.partition(":")
    return host, int(port) if port.isdigit() else 554, "/" + path


def sdp_has_backchannel(sdp_text):
    """SDP นี้มีช่องเสียงขาส่งเข้ากล้องไหม

    แยกเป็นฟังก์ชันของตัวเองเพื่อให้ทดสอบได้โดยไม่ต้องมีกล้องจริง
    a=sendonly มีผลกับ media ที่อยู่เหนือมัน จึงต้องอ่านทีละบล็อกไม่ใช่ทั้งไฟล์
    """
    in_audio = False
    for raw in sdp_text.splitlines():
        line = raw.strip()
        if line.startswith("m="):
            in_audio = line.startswith("m=audio")
            continue
        if in_audio and line == "a=sendonly":
            return True
    return False


def probe_backchannel(rtsp_url, timeout=6.0):
    """ถามกล้องว่าส่งเสียงเข้าได้ไหม

    คืน (ส่งได้ไหม, เหตุผล, คำตอบนี้เชื่อถือได้ไหม)

    ตัวสุดท้ายสำคัญ: "ต่อกล้องไม่ติดตอนนี้" กับ "กล้องบอกว่าทำไม่ได้" เป็นคนละ
    เรื่องกัน อย่างแรกเป็นแค่เหตุการณ์ชั่วคราว ถ้าเอาไปจำไว้เหมือนกันจะกลายเป็น
    ปิดปุ่มทิ้งไว้ทั้งที่กล้องอาจรองรับ
    """
    try:
        host, port, path = _split_rtsp_url(rtsp_url)
    except (ValueError, AttributeError):
        return False, f"อ่าน RTSP URL ไม่ออก: {rtsp_url!r}", True

    request = (
        f"DESCRIBE rtsp://{host}:{port}{path} RTSP/1.0\r\n"
        "CSeq: 1\r\n"
        "Accept: application/sdp\r\n"
        f"Require: {BACKCHANNEL_REQUIRE}\r\n"
        "User-Agent: thanakon-box/1.0\r\n"
        "\r\n"
    )

    buffer = b""
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.sendall(request.encode("ascii"))
            sock.settimeout(timeout)
            try:
                while len(buffer) < 65536:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    buffer += chunk
                    # กล้องไม่ปิดการเชื่อมต่อให้หลังส่ง SDP จบ ถ้ารออ่านต่อจะค้าง
                    # จนหมดเวลา — มีหัวข้อครบและมีบรรทัด m= แล้วก็พอตัดสินได้
                    if b"\r\n\r\n" in buffer and b"m=" in buffer:
                        break
            except socket.timeout:
                # หมดเวลาระหว่างอ่าน แต่สิ่งที่อ่านมาแล้วยังใช้ตัดสินได้
                pass
    except OSError as exc:
        return False, f"ต่อ RTSP ไม่ได้: {exc}", False

    if not buffer:
        return False, "กล้องไม่ตอบ DESCRIBE", False

    text = buffer.decode("utf-8", "replace")
    status_line = text.split("\r\n", 1)[0].strip()

    if " 401" in status_line or " 403" in status_line:
        # ตอบแบบนี้แปลว่าคุยกันรู้เรื่อง แต่เรายังไม่ได้ยืนยันตัวตน
        # ยังสรุปเรื่อง backchannel ไม่ได้
        return False, f"RTSP ต้องยืนยันตัวตน ({status_line})", False
    if " 200" not in status_line:
        # 551 Option not supported = กล้องบอกตรง ๆ ว่าไม่รองรับ ถือว่าสรุปได้
        return False, f"กล้องปฏิเสธ DESCRIBE ({status_line})", True

    if sdp_has_backchannel(text):
        return True, "กล้องเปิดช่องเสียงขาเข้า (พบ a=sendonly)", True
    return False, "กล้องไม่มีช่องเสียงขาเข้าใน SDP (ไม่พบ a=sendonly)", True


def backchannel_supported(rtsp_url, timeout=6.0):
    """เหมือน probe_backchannel แต่จำผลไว้ชั่วคราว — ใช้กับ /camera/status

    จำเฉพาะคำตอบที่เชื่อถือได้ ถ้าต่อกล้องไม่ติดตอนนั้นจะไม่จำ รอบหน้าจะลองใหม่
    ไม่งั้นกล้องสะดุดทีเดียวแล้วปุ่มหายไป 5 นาทีโดยไม่มีเหตุผล
    """
    now = time.monotonic()
    with _backchannel_lock:
        cached = _backchannel_cache.get(rtsp_url)
        if cached and now - cached[0] < BACKCHANNEL_CACHE_SECONDS:
            return cached[1], cached[2]

    supported, detail, conclusive = probe_backchannel(rtsp_url, timeout=timeout)

    if conclusive:
        with _backchannel_lock:
            _backchannel_cache[rtsp_url] = (now, supported, detail)
    return supported, detail


# ===================================================================
# ffmpeg ตัวเดียวแจกเสียงให้ผู้ฟังทุกคน (AudioHub)
#
# ทำไมต้องมี — เจอสองอย่างจากการทดสอบกับเครื่องจริง:
#
#   1. ตัวเล่นเสียงฝั่งแอปไม่ยอมปิดสาย
#      just_audio บน Android ตั้งพร็อกซีในเครื่องเพื่อแนบ header ให้ ExoPlayer
#      กดหยุด (แม้ dispose ตัวเล่นทิ้ง) พร็อกซีตัวนั้นก็ยังคาสายไว้กับเรา
#      เซิร์ฟเวอร์จึงไม่เห็นว่า "ไม่มีคนฟังแล้ว" — วัดได้ว่าสายค้างเกิน 77 วินาที
#      หลังผู้ใช้กดหยุดไปแล้ว
#
#   2. หนึ่งคำขอ = หนึ่ง ffmpeg = หนึ่ง RTSP กับกล้อง
#      กล้องรับได้จำกัด พอสะสมหลายตัวมันจะช้าลงจนภาพนิ่งกับคำสั่งหมุนพลอยหลุด
#      (เคยวัดได้ 13 ตัวค้างจากการกดฟังไม่กี่ครั้ง)
#
# ตัวนี้แก้ด้วยการให้มี ffmpeg ได้ทีละตัวเท่านั้น ไม่ว่าจะมีคนฟังกี่คน และตั้ง
# เพดานอายุไว้ให้มันปิดตัวเองได้แม้ไม่มีใครบอกว่าเลิกฟังแล้ว
# ===================================================================

# ผู้ฟังหนึ่งรายค้างคิวได้เท่านี้ก้อน (~4KB/ก้อน) เกินกว่านี้ทิ้งก้อนเก่าทิ้ง
# ผู้ฟังที่อืดจะได้ไม่ถ่วงคนอื่นและไม่ทำให้หน่วยความจำบวม
LISTENER_QUEUE_SIZE = 64

# ไม่มีใครฟังนานเท่านี้ = ปิด ffmpeg (เผื่อผู้ฟังคนสุดท้ายตัดสายไปเงียบ ๆ)
IDLE_GRACE_SECONDS = 5.0

# ffmpeg เปิดอยู่แต่ไม่ส่งอะไรมานานเท่านี้ = ถือว่ามันค้าง ให้ปิดทิ้ง
#
# กล้องปกติเริ่มส่งเสียงภายใน 7-9 วินาที ถ้าเกินนี้ไปมากแปลว่าต่อไม่ติดจริง
# (เคสที่เจอบ่อยสุด: มี ffmpeg ตัวเก่าค้างยึด RTSP สายเดียวของกล้องไว้อยู่
#  ตัวใหม่จึงต่อได้แต่ไม่มีข้อมูลไหลมาเลย)
NO_DATA_TIMEOUT_SECONDS = 20.0

# ตัวเฝ้าระวังตื่นมาตรวจทุกกี่วินาที
WATCHDOG_TICK_SECONDS = 1.0


class AudioHub:
    """ผู้จัดการ ffmpeg ตัวเดียวที่แจกเสียงให้ผู้ฟังหลายราย"""

    def __init__(self, make_stream, max_seconds=600.0):
        self._make_stream = make_stream
        self._max_seconds = max_seconds
        self._lock = threading.Lock()
        self._listeners = []
        self._stream = None
        self._worker = None
        self._stop = threading.Event()
        # "ยังใช้งานได้อยู่" — ห้ามใช้ _worker.is_alive() แทนตัวนี้
        # เธรดที่กำลังอยู่ใน finally: _shutdown() ก็ยังนับว่า alive ผู้ฟังใหม่
        # จะไปเกาะ worker ที่กำลังจะตายแล้วรอเก้อจนหมดเวลา 30 วินาที
        self._running = False
        self._last_chunk_at = None

    # -- ฝั่งผู้ฟัง --------------------------------------------------

    def subscribe(self):
        """ขอคิวเสียงของตัวเอง — เริ่ม ffmpeg ให้ถ้ายังไม่มีใครเปิดไว้"""
        listener = queue.Queue(maxsize=LISTENER_QUEUE_SIZE)
        with self._lock:
            self._listeners.append(listener)
            if not self._running:
                self._start_locked()
        return listener

    def unsubscribe(self, listener):
        with self._lock:
            if listener in self._listeners:
                self._listeners.remove(listener)

    def read(self, listener, timeout=30.0):
        """ก้อนถัดไปของผู้ฟังรายนี้ — คืน b"" เมื่อสตรีมจบหรือรอนานเกินไป"""
        try:
            chunk = listener.get(timeout=timeout)
        except queue.Empty:
            return b""
        return chunk if chunk is not None else b""

    @property
    def listener_count(self):
        with self._lock:
            return len(self._listeners)

    # -- ฝั่งผู้ผลิต ------------------------------------------------

    def _start_locked(self):
        self._stop.clear()
        self._stream = self._make_stream()
        self._running = True
        self._last_chunk_at = time.monotonic()
        self._worker = threading.Thread(target=self._pump, daemon=True)
        self._worker.start()
        threading.Thread(target=self._watch, args=(self._stream,), daemon=True).start()

    def _watch(self, stream):
        """ตัวเฝ้าระวัง — ปลดล็อก _pump ที่ค้างอยู่ใน stream.read()

        ทำไมต้องมี: _pump บล็อกอยู่ที่ self._stream.read() ซึ่งไม่มีวันคืนค่า
        ถ้า ffmpeg เปิดอยู่แต่ไม่ส่งข้อมูล เงื่อนไขทางออกทุกข้อใน _pump
        (เพดานอายุ, ไม่มีคนฟัง, _stop) ถูกตรวจ "หลัง" อ่านข้อมูลได้สำเร็จเท่านั้น
        pump จึงค้างถาวร และเพราะ hub เป็นตัวเดียวใช้ร่วมกันทั้งระบบ
        คนที่กดฟังทีหลังทุกคนจะได้ 0 ไบต์ไปเรื่อย ๆ จนกว่าจะ restart backend

        เกิดขึ้นจริงบน production: จับได้ว่า ffmpeg อายุ 715 วินาที แต่กิน CPU
        แค่ 0.3 วินาที และยังยึด RTSP สายเดียวของกล้องไว้

        ตัวนี้ตรวจจากข้างนอกแทน ครบเงื่อนไขเมื่อไรก็ปิด stream ทิ้ง
        การปิด stream ทำให้ read() ที่ค้างอยู่คืน b"" ทันที pump จึงหลุดออกมา
        เก็บกวาดตัวเองได้ตามปกติ
        """
        started = time.monotonic()
        idle_since = None
        while not self._stop.is_set():
            time.sleep(WATCHDOG_TICK_SECONDS)
            with self._lock:
                if self._stream is not stream:
                    return                      # รอบใหม่เริ่มแล้ว ตัวนี้หมดหน้าที่
                listeners = len(self._listeners)
                last = self._last_chunk_at or started

            now = time.monotonic()
            reason = None
            if now - last > NO_DATA_TIMEOUT_SECONDS:
                reason = "ffmpeg ไม่ส่งข้อมูลมาเกิน %.0f วินาที" % NO_DATA_TIMEOUT_SECONDS
            elif now - started > self._max_seconds:
                reason = "ครบเพดานอายุสตรีม"
            elif listeners == 0:
                idle_since = idle_since or now
                if now - idle_since > IDLE_GRACE_SECONDS:
                    reason = "ไม่มีผู้ฟังเหลือแล้ว"
            else:
                idle_since = None

            if reason:
                stream.close()                  # ปลดล็อก read() ที่ค้างอยู่
                return

    def _pump(self):
        started = time.monotonic()
        idle_since = None
        try:
            while not self._stop.is_set():
                chunk = self._stream.read()
                if not chunk:
                    break

                # ให้ตัวเฝ้าระวังรู้ว่าข้อมูลยังไหลอยู่ (ดู _watch)
                with self._lock:
                    self._last_chunk_at = time.monotonic()

                if time.monotonic() - started > self._max_seconds:
                    # เพดานอายุ — กันสตรีมที่ไม่มีใครฟังแล้วแต่สายยังไม่ถูกปิด
                    # ค้างจับกล้องไว้ทั้งคืน แอปต่อใหม่เองได้ถ้ายังอยากฟัง
                    break

                with self._lock:
                    listeners = list(self._listeners)

                if not listeners:
                    idle_since = idle_since or time.monotonic()
                    if time.monotonic() - idle_since > IDLE_GRACE_SECONDS:
                        break
                    continue
                idle_since = None

                for listener in listeners:
                    self._push(listener, chunk)
        finally:
            self._shutdown()

    @staticmethod
    def _push(listener, chunk):
        try:
            listener.put_nowait(chunk)
        except queue.Full:
            # ผู้ฟังรายนี้ตามไม่ทัน — ทิ้งก้อนเก่าสุดแล้วใส่ก้อนใหม่แทน
            # เสียงสดควรตามเวลาจริง ดีกว่าถ่วงให้ทุกคนช้าตาม
            try:
                listener.get_nowait()
                listener.put_nowait(chunk)
            except (queue.Empty, queue.Full):
                pass

    def _shutdown(self):
        with self._lock:
            # ปลดธงก่อนอย่างอื่น — ผู้ฟังที่เข้ามาระหว่างนี้จะได้เริ่มรอบใหม่
            # แทนที่จะไปเกาะ worker ตัวที่กำลังจะตายแล้วรอเก้อ
            self._running = False
            stream, self._stream = self._stream, None
            listeners, self._listeners = self._listeners, []
            self._worker = None
        if stream is not None:
            stream.close()
        for listener in listeners:
            try:
                listener.put_nowait(None)      # สัญญาณ "จบแล้ว"
            except Exception:
                pass

    def close(self):
        """สั่งปิดทันที (ใช้ตอนปิดเซิร์ฟเวอร์/เขียนเทสต์)"""
        self._stop.set()
        worker = self._worker
        if worker is not None and worker.is_alive():
            worker.join(timeout=5)
        self._shutdown()
