import threading
from dataclasses import dataclass
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import (
    HTTPBasicAuthHandler,
    HTTPDigestAuthHandler,
    HTTPPasswordMgrWithDefaultRealm,
    Request,
    build_opener,
    urlopen,
)

from camera_onvif import OnvifError, OnvifPtz


PTZ_ACTIONS = ("left", "right", "up", "down", "zoom_in", "zoom_out", "stop")
PTZ_PROFILES = ("digital", "onvif", "hi3510", "ptzctrl", "hy-cgi", "custom")


@dataclass(frozen=True)
class PtzResult:
    ok: bool
    message: str


def host_from_url(url, default="192.168.1.101"):
    parsed = urlparse(url)
    return parsed.hostname or default


def build_base_url(host, port=80):
    if not host:
        raise ValueError("PTZ host is required")
    if int(port) == 80:
        return f"http://{host}"
    return f"http://{host}:{int(port)}"


def build_ptz_urls(
    profile,
    host,
    action,
    port=80,
    speed=8,
    pan_speed=12,
    tilt_speed=10,
    zoom_speed=4,
):
    if action not in PTZ_ACTIONS:
        raise ValueError(f"Unsupported PTZ action: {action}")

    base_url = build_base_url(host, port)

    if profile == "hi3510":
        action_map = {
            "left": "left",
            "right": "right",
            "up": "up",
            "down": "down",
            "zoom_in": "zoomin",
            "zoom_out": "zoomout",
            "stop": "stop",
        }
        ptz_action = action_map[action]
        return [
            f"{base_url}/cgi-bin/hi3510/ptzctrl.cgi?-step=0&-speed={int(speed)}&-act={ptz_action}"
        ]

    if profile == "ptzctrl":
        action_map = {
            "left": "left",
            "right": "right",
            "up": "up",
            "down": "down",
            "zoom_in": "zoomin",
            "zoom_out": "zoomout",
        }
        if action == "stop":
            return [
                f"{base_url}/cgi-bin/ptzctrl.cgi?ptzcmd&ptzstop&{int(pan_speed)}&{int(tilt_speed)}",
                f"{base_url}/cgi-bin/ptzctrl.cgi?ptzcmd&zoomstop&{int(zoom_speed)}",
            ]
        ptz_action = action_map[action]
        if action.startswith("zoom"):
            return [
                f"{base_url}/cgi-bin/ptzctrl.cgi?ptzcmd&{ptz_action}&{int(zoom_speed)}"
            ]
        return [
            f"{base_url}/cgi-bin/ptzctrl.cgi?ptzcmd&{ptz_action}&{int(pan_speed)}&{int(tilt_speed)}"
        ]

    if profile == "hy-cgi":
        action_map = {
            "left": "left",
            "right": "right",
            "up": "up",
            "down": "down",
            "zoom_in": "zoomin",
            "zoom_out": "zoomout",
            "stop": "stop",
        }
        ptz_action = action_map[action]
        return [f"{base_url}/hy-cgi/ptz.cgi?cmd=ptzctrl&act={ptz_action}"]

    raise ValueError(f"PTZ profile does not build URLs: {profile}")


_onvif_clients = {}
_onvif_clients_lock = threading.Lock()


def get_onvif_client(host, port=80, username=None, password=None, timeout=5):
    """Reuse one connected client per camera so buttons do not re-run discovery."""
    key = (host, int(port), username or "")
    with _onvif_clients_lock:
        client = _onvif_clients.get(key)
        if client is None or client.password != (password or ""):
            client = OnvifPtz(host, port, username, password, timeout)
            _onvif_clients[key] = client
        return client


def send_onvif_action(
    host,
    action,
    port=80,
    username=None,
    password=None,
    speed=0.6,
    zoom_speed=0.6,
    invert_pan=False,
    invert_tilt=False,
    reset_to_home=True,
    timeout=5,
):
    """Drive physical PTZ over ONVIF.

    `action` accepts every entry in PTZ_ACTIONS plus "home". Movement starts and
    keeps going until "stop" is sent, matching how the CGI profiles behave.
    """
    if action not in PTZ_ACTIONS and action != "home":
        raise ValueError(f"Unsupported PTZ action: {action}")

    try:
        client = get_onvif_client(host, port, username, password, timeout)
        if action == "home" and not reset_to_home:
            return PtzResult(False, "Home position is disabled")
        client.move(
            action,
            speed=speed,
            zoom_speed=zoom_speed,
            invert_pan=invert_pan,
            invert_tilt=invert_tilt,
        )
        return PtzResult(True, f"ONVIF {action} ok")
    except (OnvifError, ValueError) as exc:
        return PtzResult(False, f"ONVIF error: {exc}")


def request_url(url, username=None, password=None, timeout=2):
    request = Request(url, headers={"User-Agent": "camera-ptz/1.0"})

    if username:
        password_manager = HTTPPasswordMgrWithDefaultRealm()
        password_manager.add_password(None, url, username, password or "")
        opener = build_opener(
            HTTPDigestAuthHandler(password_manager),
            HTTPBasicAuthHandler(password_manager),
        )
    else:
        opener = None

    try:
        if opener is None:
            response = urlopen(request, timeout=timeout)
        else:
            response = opener.open(request, timeout=timeout)
        with response:
            response.read(256)
            return PtzResult(True, f"HTTP {response.status}")
    except HTTPError as exc:
        return PtzResult(False, f"HTTP {exc.code}")
    except URLError as exc:
        return PtzResult(False, f"URL error: {exc.reason}")
    except OSError as exc:
        return PtzResult(False, f"Network error: {exc}")


def send_ptz_urls(urls: Iterable[str], username=None, password=None, timeout=2):
    messages = []
    for url in urls:
        result = request_url(url, username=username, password=password, timeout=timeout)
        messages.append(result.message)
        if not result.ok:
            return PtzResult(False, "; ".join(messages))
    return PtzResult(True, "; ".join(messages))


def send_ptz_action(
    profile,
    host,
    action,
    port=80,
    username=None,
    password=None,
    speed=8,
    pan_speed=12,
    tilt_speed=10,
    zoom_speed=4,
    timeout=2,
    onvif_speed=0.6,
    onvif_zoom_speed=0.6,
    invert_pan=False,
    invert_tilt=False,
):
    if profile == "onvif":
        return send_onvif_action(
            host=host,
            action=action,
            port=port,
            username=username,
            password=password,
            speed=onvif_speed,
            zoom_speed=onvif_zoom_speed,
            invert_pan=invert_pan,
            invert_tilt=invert_tilt,
            timeout=max(timeout, 5),
        )

    urls = build_ptz_urls(
        profile=profile,
        host=host,
        action=action,
        port=port,
        speed=speed,
        pan_speed=pan_speed,
        tilt_speed=tilt_speed,
        zoom_speed=zoom_speed,
    )
    return send_ptz_urls(urls, username=username, password=password, timeout=timeout)
