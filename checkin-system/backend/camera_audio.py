"""ดึงเสียงจากไมค์ของกล้อง RTSP ออกมาเป็นสตรีม AAC ให้แอปเล่นได้

กล้องส่งเสียงมาเป็น G.711 (PCMA 8kHz) ซึ่งเล่นตรงๆ ผ่าน HTTP ไม่ได้
จึงให้ ffmpeg แปลงเป็น AAC/ADTS ที่ ExoPlayer บน Android เล่นสตรีมสดได้เลย

เป็นเสียง "ขาเข้า" อย่างเดียว — กล้องรุ่นนี้ไม่มีลำโพงและไม่เปิด RTSP
backchannel จึงพูดกลับออกกล้องไม่ได้ (ตรวจแล้วด้วย DESCRIBE + Require:
www.onvif.org/ver20/backchannel ซึ่งกล้องตอบ SDP เดิมไม่มี track ขาส่ง)
"""

import shutil
import subprocess
import sys
import threading
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
    creationflags = 0
    if sys.platform.startswith("win"):
        creationflags = subprocess.CREATE_NO_WINDOW

    return subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
        creationflags=creationflags,
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


def stop_process(process):
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
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
