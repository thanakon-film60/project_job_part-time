"""Minimal ONVIF PTZ client built on the standard library only.

The cameras used here answer SOAP on http://<host>/onvif/*. Physical movement
is driven by ContinuousMove plus a Stop, because AbsoluteMove and RelativeMove
are rejected by the firmware ("space not supported by the PTZ Node").
"""

import argparse
import base64
import hashlib
import http.client
import os
import sys
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import (
    HTTPBasicAuthHandler,
    HTTPDigestAuthHandler,
    HTTPPasswordMgrWithDefaultRealm,
    Request,
    build_opener,
    urlopen,
)


DEVICE_WSDL = "http://www.onvif.org/ver10/device/wsdl"
MEDIA_WSDL = "http://www.onvif.org/ver10/media/wsdl"
PTZ_WSDL = "http://www.onvif.org/ver20/ptz/wsdl"
SCHEMA_NS = "http://www.onvif.org/ver10/schema"
WSSE_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
WSU_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
PASSWORD_DIGEST = (
    "http://docs.oasis-open.org/wss/2004/01/"
    "oasis-200401-wss-username-token-profile-1.0#PasswordDigest"
)
BASE64_BINARY = (
    "http://docs.oasis-open.org/wss/2004/01/"
    "oasis-200401-wss-soap-message-security-1.0#Base64Binary"
)

DEFAULT_DEVICE_PATH = "/onvif/device_service"
PTZ_MOVES = {
    "left": (-1.0, 0.0, 0.0),
    "right": (1.0, 0.0, 0.0),
    "up": (0.0, 1.0, 0.0),
    "down": (0.0, -1.0, 0.0),
    "zoom_in": (0.0, 0.0, 1.0),
    "zoom_out": (0.0, 0.0, -1.0),
}


class OnvifError(Exception):
    pass


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def find_all(element, name):
    return [node for node in element.iter() if local_name(node.tag) == name]


def find_first(element, name):
    for node in element.iter():
        if local_name(node.tag) == name:
            return node
    return None


def security_header(username, password):
    if not username:
        return ""

    nonce = os.urandom(16)
    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    digest = hashlib.sha1(
        nonce + created.encode("utf-8") + (password or "").encode("utf-8")
    ).digest()
    return (
        f'<s:Header><Security s:mustUnderstand="1" xmlns="{WSSE_NS}">'
        f"<UsernameToken><Username>{username}</Username>"
        f'<Password Type="{PASSWORD_DIGEST}">'
        f"{base64.b64encode(digest).decode('ascii')}</Password>"
        f'<Nonce EncodingType="{BASE64_BINARY}">'
        f"{base64.b64encode(nonce).decode('ascii')}</Nonce>"
        f'<Created xmlns="{WSU_NS}">{created}</Created>'
        f"</UsernameToken></Security></s:Header>"
    )


def build_envelope(body, username=None, password=None):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
        + security_header(username, password)
        + '<s:Body xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        + body
        + "</s:Body></s:Envelope>"
    ).encode("utf-8")


def fault_text(xml_text):
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return xml_text.strip()[:200] or "Malformed SOAP response"

    for name in ("Text", "faultstring", "Value"):
        node = find_first(root, name)
        if node is not None and (node.text or "").strip():
            return node.text.strip()
    return "Unknown SOAP fault"


class OnvifPtz:
    """Talks ONVIF PTZ to one camera. Call connect() before moving."""

    def __init__(self, host, port=80, username=None, password=None, timeout=5,
                 snapshot_timeout=None):
        if not host:
            raise ValueError("ONVIF host is required")
        self.host = host
        self.port = int(port)
        self.username = username or None
        self.password = password or ""
        self.timeout = timeout
        # ดึงภาพ JPEG ช้ากว่าคุย SOAP มาก จึงแยกเพดานเวลาไว้คนละตัว
        self.snapshot_timeout = snapshot_timeout or timeout

        base = f"http://{host}" if self.port == 80 else f"http://{host}:{self.port}"
        self.device_url = base + DEFAULT_DEVICE_PATH
        self.ptz_url = base + "/onvif/ptz_service"
        self.media_url = base + "/onvif/media_service"
        self.profile_token = None
        self.home_supported = False
        self.snapshot_url = None
        self._lock = threading.Lock()

        # opener สำหรับดึงภาพ สร้างครั้งเดียวแล้วใช้ซ้ำ — สร้างใหม่ทุกเฟรม
        # เปลืองเปล่าและทำให้ urllib ลืมว่าเคยยืนยันตัวตนไปแล้ว
        self._snapshot_opener = None
        # กล้องรับ Basic หรือ Digest — จำไว้หลังสำเร็จครั้งแรก
        # ไม่จำ = ทุกเฟรมต้องยิง 2 ครั้ง (โดน 401 ก่อน แล้วค่อยยิงซ้ำพร้อม
        # ข้อมูลยืนยันตัวตน) เท่ากับกล้องรับภาระเป็นสองเท่าโดยไม่จำเป็น
        self._auth_mode = None

    def call(self, url, body):
        request = Request(
            url,
            data=build_envelope(body, self.username, self.password),
            headers={
                "Content-Type": "application/soap+xml; charset=utf-8",
                "User-Agent": "camera-onvif/1.0",
            },
        )
        try:
            with urlopen(request, timeout=self.timeout) as response:
                return ET.fromstring(response.read())
        except HTTPError as exc:
            raise OnvifError(fault_text(exc.read().decode("utf-8", "replace"))) from exc
        except URLError as exc:
            raise OnvifError(f"URL error: {exc.reason}") from exc
        except ET.ParseError as exc:
            raise OnvifError(f"Malformed SOAP response: {exc}") from exc
        except OSError as exc:
            raise OnvifError(f"Network error: {exc}") from exc

    def device_information(self):
        root = self.call(self.device_url, f'<GetDeviceInformation xmlns="{DEVICE_WSDL}"/>')
        info = {}
        for key in ("Manufacturer", "Model", "FirmwareVersion", "SerialNumber", "HardwareId"):
            node = find_first(root, key)
            info[key] = (node.text or "").strip() if node is not None else ""
        return info

    def discover_services(self):
        """ถามกล้องว่า service แต่ละตัวอยู่ URL ไหน — ถามไม่ได้ก็ใช้ค่ามาตรฐานต่อ

        ค่าเริ่มต้นใน __init__ (/onvif/ptz_service, /onvif/media_service) ใช้ได้
        กับกล้องตัวนี้อยู่แล้ว ขั้นตอนนี้จึงเป็นแค่ "เผื่อกล้องวาง service ไว้
        ที่อื่น" ไม่ใช่สิ่งที่ขาดไม่ได้

        เดิมปล่อยให้ล้มทั้งการต่อ ทำให้กล้องตอบช้าครั้งเดียวก็ต่อไม่ติดทั้งชุด
        ทั้งที่ค่ามาตรฐานยังใช้ได้ — และถ้า URL มาตรฐานใช้ไม่ได้จริง ขั้นตอน
        ถัดไป (GetProfiles) จะเป็นคนบอกเองอยู่แล้ว
        """
        try:
            root = self.call(
                self.device_url,
                f'<GetServices xmlns="{DEVICE_WSDL}">'
                "<IncludeCapability>false</IncludeCapability></GetServices>",
            )
        except OnvifError:
            return

        for service in find_all(root, "Service"):
            namespace = find_first(service, "Namespace")
            address = find_first(service, "XAddr")
            if namespace is None or address is None:
                continue
            namespace_text = (namespace.text or "").strip()
            address_text = (address.text or "").strip()
            if namespace_text == PTZ_WSDL:
                self.ptz_url = address_text
            elif namespace_text == MEDIA_WSDL:
                self.media_url = address_text

    def discover_profile(self):
        root = self.call(self.media_url, f'<GetProfiles xmlns="{MEDIA_WSDL}"/>')
        profiles = find_all(root, "Profiles")
        for profile in profiles:
            if profile.get("token") and find_first(profile, "PTZConfiguration") is not None:
                return profile.get("token")
        for profile in profiles:
            if profile.get("token"):
                return profile.get("token")
        raise OnvifError("Camera reported no ONVIF media profile")

    def discover_home(self):
        try:
            root = self.call(self.ptz_url, f'<GetNodes xmlns="{PTZ_WSDL}"/>')
        except OnvifError:
            return False
        node = find_first(root, "HomeSupported")
        return node is not None and (node.text or "").strip().lower() == "true"

    def connect(self):
        with self._lock:
            return self._connect_locked()

    def _connect_locked(self):
        """ตัวต่อกล้องจริง — ผู้เรียกต้องถือ self._lock อยู่แล้ว"""
        self.discover_services()
        self.profile_token = self.discover_profile()
        self.home_supported = self.discover_home()
        return self.profile_token

    def snapshot_uri(self, refresh=False):
        """URL ของภาพนิ่ง JPEG จากกล้อง — ถามกล้องครั้งเดียวแล้วจำไว้

        refresh=True ใช้เมื่อ URL เดิมใช้ไม่ได้แล้ว (กล้องรีบูตเองแล้วเปลี่ยน
        token ท้าย URL) — ถามใหม่ครั้งเดียว โดยไม่ต้องรื้อ session ทั้งชุด
        """
        if self.snapshot_url and not refresh:
            return self.snapshot_url

        token = self.ensure_connected()
        root = self.call(
            self.media_url,
            f'<GetSnapshotUri xmlns="{MEDIA_WSDL}">'
            f"<ProfileToken>{token}</ProfileToken></GetSnapshotUri>",
        )
        node = find_first(root, "Uri")
        if node is None or not (node.text or "").strip():
            raise OnvifError("Camera did not report a snapshot URI")
        self.snapshot_url = node.text.strip()
        # URL เปลี่ยน = วิธียืนยันตัวตนที่ตกลงไว้เดิมอาจใช้ไม่ได้ ให้ตกลงกันใหม่
        self._snapshot_opener = None
        self._auth_mode = None
        return self.snapshot_url

    def _basic_header(self):
        raw = f"{self.username}:{self.password}".encode("utf-8")
        return "Basic " + base64.b64encode(raw).decode("ascii")

    def _open_snapshot(self, url, timeout):
        """ยิงขอภาพ 1 ครั้ง ด้วยวิธียืนยันตัวตนที่ประหยัดที่สุดเท่าที่รู้

        กล้องส่วนใหญ่รับ Basic ซึ่งแนบไปกับคำขอแรกได้เลย = 1 คำขอต่อ 1 เฟรม
        ถ้ากล้องไม่รับค่อยถอยไปใช้ opener ที่รองรับ Digest แล้วจำไว้

        ของเดิมสร้าง opener ใหม่ทุกเฟรม ทำให้ทุกเฟรมต้องยิงสองครั้ง (โดน 401
        ก่อน แล้วค่อยยิงซ้ำพร้อมข้อมูลยืนยันตัวตน) กล้องจึงรับภาระเป็นสองเท่า
        """
        headers = {"User-Agent": "camera-onvif/1.0"}

        if not self.username:
            return urlopen(Request(url, headers=headers), timeout=timeout)

        if self._auth_mode in (None, "basic"):
            try:
                request = Request(
                    url,
                    headers={**headers, "Authorization": self._basic_header()},
                )
                response = urlopen(request, timeout=timeout)
                self._auth_mode = "basic"
                return response
            except HTTPError as exc:
                if exc.code != 401 or self._auth_mode == "basic":
                    raise
                # กล้องไม่รับ Basic — จำไว้แล้วใช้ Digest ตั้งแต่นี้ไป
                self._auth_mode = "digest"

        if self._snapshot_opener is None:
            manager = HTTPPasswordMgrWithDefaultRealm()
            manager.add_password(None, url, self.username, self.password)
            self._snapshot_opener = build_opener(
                HTTPDigestAuthHandler(manager),
                HTTPBasicAuthHandler(manager),
            )
        return self._snapshot_opener.open(
            Request(url, headers=headers), timeout=timeout
        )

    def fetch_snapshot(self, timeout=None):
        """ภาพนิ่งล่าสุดเป็น bytes ของไฟล์ JPEG

        พลาดครั้งแรกจะถาม URL ภาพใหม่แล้วลองอีกครั้ง — กล้องรีบูตเองกลางดึก
        เป็นเรื่องปกติ และ token ท้าย URL ภาพก็หมดอายุตามไปด้วย การลองใหม่
        ตรงนี้ทำให้ฝั่งแอปแทบไม่เห็นภาพสะดุดเลย
        """
        timeout = timeout or self.snapshot_timeout

        try:
            return self._fetch_snapshot_once(self.snapshot_uri(), timeout)
        except OnvifError:
            if not self.snapshot_url:
                raise

        # URL เดิมใช้ไม่ได้ — ถามใหม่แล้วลองอีกรอบ รอบนี้พลาดค่อยยอมแพ้
        return self._fetch_snapshot_once(self.snapshot_uri(refresh=True), timeout)

    def _fetch_snapshot_once(self, url, timeout):
        try:
            with self._open_snapshot(url, timeout) as response:
                data = response.read()
        except HTTPError as exc:
            raise OnvifError(f"Snapshot HTTP {exc.code}") from exc
        except URLError as exc:
            raise OnvifError(f"Snapshot URL error: {exc.reason}") from exc
        except OSError as exc:
            raise OnvifError(f"Snapshot network error: {exc}") from exc
        except http.client.HTTPException as exc:
            # กล้องตัดสายกลางส่งภาพจะได้ IncompleteRead/BadStatusLine ซึ่ง
            # ไม่ใช่ OSError จึงเคยหลุดออกไปเป็น error 500 ที่ไม่มีใครดัก
            # ทั้งที่มันคือ "ภาพสะดุด" ธรรมดาที่ควรลองใหม่รอบหน้า
            raise OnvifError(f"Snapshot stream error: {type(exc).__name__}") from exc
        except ValueError as exc:
            # URL ที่กล้องบอกมาผิดรูปแบบ/มีอักขระที่ส่งเป็น HTTP ไม่ได้
            raise OnvifError(f"Snapshot URL is unusable: {exc}") from exc

        if not data.startswith(b"\xff\xd8"):
            raise OnvifError("Camera returned something that is not a JPEG image")
        return data

    def ensure_connected(self):
        """คืน profile token — ต่อกล้องให้เองถ้ายังไม่ได้ต่อ

        ล็อกไว้เพราะหลายคำขอวิ่งพร้อมกันได้ (ภาพนิ่งยิงทุกวินาที + ปุ่มหมุน)
        ถ้าไม่ล็อก ทุกเธรดจะเห็น profile_token เป็น None พร้อมกัน แล้วแห่กัน
        ต่อกล้องใหม่ทีเดียวหลายชุด ซึ่งเป็นจังหวะที่กล้องมักตอบไม่ทันจนหลุด
        """
        if self.profile_token is not None:
            return self.profile_token

        with self._lock:
            # เธรดอื่นอาจต่อเสร็จไปแล้วระหว่างที่รอคิว
            if self.profile_token is None:
                self._connect_locked()
            return self.profile_token

    def continuous_move(self, pan=0.0, tilt=0.0, zoom=0.0):
        token = self.ensure_connected()
        velocity = f'<tt:PanTilt x="{pan:.3f}" y="{tilt:.3f}" xmlns:tt="{SCHEMA_NS}"/>'
        if zoom:
            velocity += f'<tt:Zoom x="{zoom:.3f}" xmlns:tt="{SCHEMA_NS}"/>'
        self.call(
            self.ptz_url,
            f'<ContinuousMove xmlns="{PTZ_WSDL}"><ProfileToken>{token}</ProfileToken>'
            f"<Velocity>{velocity}</Velocity></ContinuousMove>",
        )

    def stop(self):
        token = self.ensure_connected()
        self.call(
            self.ptz_url,
            f'<Stop xmlns="{PTZ_WSDL}"><ProfileToken>{token}</ProfileToken>'
            "<PanTilt>true</PanTilt><Zoom>true</Zoom></Stop>",
        )

    def goto_home(self):
        token = self.ensure_connected()
        self.call(
            self.ptz_url,
            f'<GotoHomePosition xmlns="{PTZ_WSDL}">'
            f"<ProfileToken>{token}</ProfileToken></GotoHomePosition>",
        )

    def move(self, action, speed=0.6, zoom_speed=0.6, invert_pan=False, invert_tilt=False):
        """Start moving. The caller is responsible for calling stop()."""
        if action == "stop":
            self.stop()
            return
        if action == "home":
            self.goto_home()
            return
        if action not in PTZ_MOVES:
            raise ValueError(f"Unsupported PTZ action: {action}")

        pan, tilt, zoom = PTZ_MOVES[action]
        if invert_pan:
            pan = -pan
        if invert_tilt:
            tilt = -tilt
        self.continuous_move(pan * speed, tilt * speed, zoom * zoom_speed)

    def move_pulse(self, action, duration=0.4, speed=0.6, zoom_speed=0.6,
                   invert_pan=False, invert_tilt=False):
        """Move for `duration` seconds, then stop. Blocks for that long."""
        if action in ("stop", "home"):
            self.move(action)
            return
        self.move(
            action,
            speed=speed,
            zoom_speed=zoom_speed,
            invert_pan=invert_pan,
            invert_tilt=invert_tilt,
        )
        time.sleep(max(0.05, duration))
        self.stop()


def parse_args():
    parser = argparse.ArgumentParser(description="Probe and test ONVIF PTZ on a camera.")
    parser.add_argument("--host", default=os.environ.get("CAMERA_PTZ_HOST", "192.168.1.101"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CAMERA_PTZ_PORT", "80")))
    parser.add_argument("--username", default=os.environ.get("CAMERA_PTZ_USERNAME", ""))
    parser.add_argument("--password", default=os.environ.get("CAMERA_PTZ_PASSWORD", ""))
    parser.add_argument(
        "--action",
        choices=sorted(PTZ_MOVES) + ["stop", "home"],
        help="Send one PTZ action, then stop.",
    )
    parser.add_argument("--duration", type=float, default=0.8, help="Seconds to move.")
    parser.add_argument("--speed", type=float, default=0.6, help="Pan/tilt speed, 0..1.")
    return parser.parse_args()


def main():
    args = parse_args()
    camera = OnvifPtz(args.host, args.port, args.username, args.password)

    try:
        token = camera.connect()
    except OnvifError as exc:
        print(f"ONVIF connect failed: {exc}", file=sys.stderr)
        return 1

    try:
        info = camera.device_information()
        print(f"Device: {info['Manufacturer']} {info['Model']} fw {info['FirmwareVersion']}")
    except OnvifError as exc:
        print(f"Device information unavailable: {exc}")

    print(f"PTZ service:  {camera.ptz_url}")
    print(f"Profile:      {token}")
    print(f"Home support: {camera.home_supported}")

    if args.action:
        print(f"Sending {args.action} for {args.duration:.1f}s...")
        try:
            camera.move_pulse(args.action, duration=args.duration, speed=args.speed)
        except OnvifError as exc:
            print(f"PTZ command failed: {exc}", file=sys.stderr)
            return 1
        print("PTZ command completed.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
