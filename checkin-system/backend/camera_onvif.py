"""Minimal ONVIF PTZ client built on the standard library only.

The cameras used here answer SOAP on http://<host>/onvif/*. Physical movement
is driven by ContinuousMove plus a Stop, because AbsoluteMove and RelativeMove
are rejected by the firmware ("space not supported by the PTZ Node").
"""

import argparse
import base64
import hashlib
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

    def __init__(self, host, port=80, username=None, password=None, timeout=5):
        if not host:
            raise ValueError("ONVIF host is required")
        self.host = host
        self.port = int(port)
        self.username = username or None
        self.password = password or ""
        self.timeout = timeout

        base = f"http://{host}" if self.port == 80 else f"http://{host}:{self.port}"
        self.device_url = base + DEFAULT_DEVICE_PATH
        self.ptz_url = base + "/onvif/ptz_service"
        self.media_url = base + "/onvif/media_service"
        self.profile_token = None
        self.home_supported = False
        self.snapshot_url = None
        self._lock = threading.Lock()

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
        root = self.call(
            self.device_url,
            f'<GetServices xmlns="{DEVICE_WSDL}">'
            "<IncludeCapability>false</IncludeCapability></GetServices>",
        )
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
            self.discover_services()
            self.profile_token = self.discover_profile()
            self.home_supported = self.discover_home()
            return self.profile_token

    def snapshot_uri(self):
        """URL ของภาพนิ่ง JPEG จากกล้อง — ถามกล้องครั้งเดียวแล้วจำไว้"""
        if self.snapshot_url:
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
        return self.snapshot_url

    def fetch_snapshot(self, timeout=None):
        """ภาพนิ่งล่าสุดเป็น bytes ของไฟล์ JPEG"""
        url = self.snapshot_uri()
        request = Request(url, headers={"User-Agent": "camera-onvif/1.0"})

        if self.username:
            manager = HTTPPasswordMgrWithDefaultRealm()
            manager.add_password(None, url, self.username, self.password)
            opener = build_opener(
                HTTPDigestAuthHandler(manager),
                HTTPBasicAuthHandler(manager),
            )
            open_url = opener.open
        else:
            open_url = urlopen

        try:
            with open_url(request, timeout=timeout or self.timeout) as response:
                data = response.read()
        except HTTPError as exc:
            raise OnvifError(f"Snapshot HTTP {exc.code}") from exc
        except URLError as exc:
            raise OnvifError(f"Snapshot URL error: {exc.reason}") from exc
        except OSError as exc:
            raise OnvifError(f"Snapshot network error: {exc}") from exc

        if not data.startswith(b"\xff\xd8"):
            raise OnvifError("Camera returned something that is not a JPEG image")
        return data

    def ensure_connected(self):
        if self.profile_token is None:
            self.connect()
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
