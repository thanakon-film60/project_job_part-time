import argparse
import os
import shutil
import subprocess
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk

from PIL import Image, ImageTk

from camera_ptz import (
    PTZ_ACTIONS,
    PTZ_PROFILES,
    host_from_url,
    send_ptz_action,
    send_ptz_urls,
)
from camera_view import DEFAULT_CAMERA_URL


DEFAULT_FFMPEG_PATH = r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"


def parse_args():
    parser = argparse.ArgumentParser(description="FFmpeg-based IP camera GUI.")
    parser.add_argument(
        "--url",
        default=os.environ.get("CAMERA_URL", DEFAULT_CAMERA_URL),
        help=f"RTSP camera URL. Default: {DEFAULT_CAMERA_URL}",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=int(os.environ.get("CAMERA_DISPLAY_WIDTH", "1280")),
        help="Video display width.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=int(os.environ.get("CAMERA_DISPLAY_HEIGHT", "720")),
        help="Video display height.",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=int(os.environ.get("CAMERA_DISPLAY_FPS", "15")),
        help="Display FPS decoded by FFmpeg.",
    )
    parser.add_argument(
        "--ffmpeg",
        default=os.environ.get("FFMPEG_PATH"),
        help="Path to ffmpeg.exe. Default: auto-detect.",
    )
    parser.add_argument(
        "--snapshot-dir",
        default="storage/camera-snapshots",
        help="Directory for saved snapshots.",
    )
    parser.add_argument(
        "--ptz-profile",
        choices=PTZ_PROFILES,
        default=os.environ.get("CAMERA_PTZ_PROFILE", "onvif"),
        help="PTZ mode/profile. digital does not move the physical camera.",
    )
    parser.add_argument(
        "--ptz-host",
        default=os.environ.get("CAMERA_PTZ_HOST"),
        help="Camera host for physical PTZ. Default: host from RTSP URL.",
    )
    parser.add_argument(
        "--ptz-port",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_PORT", "80")),
        help="Camera HTTP port for physical PTZ.",
    )
    parser.add_argument(
        "--ptz-username",
        default=os.environ.get("CAMERA_PTZ_USERNAME", ""),
        help="PTZ username. Prefer entering it in the GUI instead of CLI history.",
    )
    parser.add_argument(
        "--ptz-password",
        default=os.environ.get("CAMERA_PTZ_PASSWORD", ""),
        help="PTZ password. Prefer entering it in the GUI instead of CLI history.",
    )
    parser.add_argument(
        "--ptz-speed",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_SPEED", "8")),
        help="PTZ speed for hi3510 and hy-cgi style commands.",
    )
    parser.add_argument(
        "--ptz-pan-speed",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_PAN_SPEED", "12")),
        help="Pan speed for ptzctrl profile.",
    )
    parser.add_argument(
        "--ptz-tilt-speed",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_TILT_SPEED", "10")),
        help="Tilt speed for ptzctrl profile.",
    )
    parser.add_argument(
        "--ptz-zoom-speed",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_ZOOM_SPEED", "4")),
        help="Zoom speed for ptzctrl profile.",
    )
    parser.add_argument(
        "--ptz-onvif-speed",
        type=float,
        default=float(os.environ.get("CAMERA_PTZ_ONVIF_SPEED", "0.6")),
        help="ONVIF pan/tilt velocity, 0..1.",
    )
    parser.add_argument(
        "--ptz-onvif-zoom-speed",
        type=float,
        default=float(os.environ.get("CAMERA_PTZ_ONVIF_ZOOM_SPEED", "0.6")),
        help="ONVIF zoom velocity, 0..1.",
    )
    parser.add_argument(
        "--ptz-hold-ms",
        type=int,
        default=int(os.environ.get("CAMERA_PTZ_HOLD_MS", "600")),
        help="How long a click keeps the camera moving before Stop is sent.",
    )
    parser.add_argument(
        "--ptz-invert-pan",
        action="store_true",
        default=os.environ.get("CAMERA_PTZ_INVERT_PAN", "") == "1",
        help="Swap left and right if the camera is mounted mirrored.",
    )
    parser.add_argument(
        "--ptz-invert-tilt",
        action="store_true",
        default=os.environ.get("CAMERA_PTZ_INVERT_TILT", "") == "1",
        help="Swap up and down if the camera is ceiling mounted.",
    )

    for action in PTZ_ACTIONS:
        option = action.replace("_", "-")
        parser.add_argument(
            f"--ptz-{option}-url",
            default=os.environ.get(f"CAMERA_PTZ_{action.upper()}_URL"),
            help=f"HTTP GET URL for PTZ action: {action}",
        )

    return parser.parse_args()


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


class FfmpegCameraGui:
    def __init__(self, root, args):
        self.root = root
        self.args = args
        self.display_width = args.width
        self.display_height = args.height
        self.frame_size = self.display_width * self.display_height * 3
        self.snapshot_dir = Path(args.snapshot_dir)
        self.ffmpeg_path = find_ffmpeg(args.ffmpeg)
        self.ptz_urls = {
            action: getattr(args, f"ptz_{action}_url") for action in PTZ_ACTIONS
        }

        self.url_var = tk.StringVar(value=args.url)
        self.ptz_profile_var = tk.StringVar(value=args.ptz_profile)
        self.ptz_host_var = tk.StringVar(value=args.ptz_host or host_from_url(args.url))
        self.ptz_port_var = tk.StringVar(value=str(args.ptz_port))
        self.ptz_username_var = tk.StringVar(value=args.ptz_username)
        self.ptz_password_var = tk.StringVar(value=args.ptz_password)
        self.status_var = tk.StringVar(value="Starting")
        self.view_var = tk.StringVar(value="")

        self.status_lock = threading.Lock()
        self.frame_lock = threading.Lock()
        self.process_lock = threading.Lock()
        self.status_text = "Starting"
        self.latest_frame_bytes = None
        self.frame_count = 0
        self.last_frame_at = None
        self.process = None
        self.stop_event = threading.Event()
        self.reconnect_event = threading.Event()

        self.zoom = 1.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        self.photo = None
        self.stop_timer_id = None
        self.press_started_at = 0.0

        self.build_ui()
        self.bind_keys()
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        self.reader_thread = threading.Thread(target=self.reader_loop, daemon=True)
        self.reader_thread.start()
        self.root.after(33, self.refresh_video)

    def build_ui(self):
        self.root.title("IP Camera GUI - FFmpeg")
        self.root.geometry("1500x860")
        self.root.minsize(1000, 640)

        outer = ttk.Frame(self.root, padding=10)
        outer.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(1, weight=1)

        top = ttk.Frame(outer)
        top.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        top.columnconfigure(1, weight=1)

        ttk.Label(top, text="RTSP URL").grid(row=0, column=0, sticky="w")
        ttk.Entry(top, textvariable=self.url_var).grid(
            row=0,
            column=1,
            sticky="ew",
            padx=8,
        )
        ttk.Button(top, text="Reconnect", command=self.reconnect).grid(
            row=0,
            column=2,
            padx=(0, 8),
        )
        ttk.Button(top, text="Snapshot", command=self.snapshot).grid(row=0, column=3)

        self.video_canvas = tk.Canvas(
            outer,
            bg="#000000",
            width=self.display_width,
            height=self.display_height,
            bd=0,
            highlightthickness=0,
        )
        self.video_canvas.grid(row=1, column=0, sticky="nsew")
        self.video_canvas.bind("<Configure>", self.resize_video_area)
        self.canvas_image_id = None
        self.canvas_text_id = self.video_canvas.create_text(
            self.display_width // 2,
            self.display_height // 2,
            fill="#d7dde6",
            text="Waiting for camera video...",
        )

        controls = ttk.Frame(outer, padding=(12, 0, 0, 0))
        controls.grid(row=1, column=1, sticky="ns")

        ttk.Label(controls, text="Move").grid(row=0, column=0, columnspan=3, pady=(0, 8))
        self.add_move_button(controls, "Up", "up", row=1, column=1)
        self.add_move_button(controls, "Left", "left", row=2, column=0)
        ttk.Button(controls, text="Reset", command=self.reset_view).grid(
            row=2,
            column=1,
            sticky="ew",
            padx=2,
            pady=2,
        )
        self.add_move_button(controls, "Right", "right", row=2, column=2)
        self.add_move_button(controls, "Down", "down", row=3, column=1)

        ttk.Separator(controls).grid(
            row=4,
            column=0,
            columnspan=3,
            sticky="ew",
            pady=14,
        )
        self.add_move_button(controls, "Zoom +", "zoom_in", row=5, column=0, columnspan=3)
        self.add_move_button(controls, "Zoom -", "zoom_out", row=6, column=0, columnspan=3)
        ttk.Button(controls, text="Physical PTZ Stop", command=lambda: self.ptz("stop")).grid(
            row=7,
            column=0,
            columnspan=3,
            sticky="ew",
            pady=(14, 2),
        )
        ttk.Separator(controls).grid(
            row=8,
            column=0,
            columnspan=3,
            sticky="ew",
            pady=14,
        )

        ttk.Label(controls, text="PTZ Profile").grid(row=9, column=0, columnspan=3, sticky="w")
        ttk.Combobox(
            controls,
            values=PTZ_PROFILES,
            textvariable=self.ptz_profile_var,
            state="readonly",
            width=18,
        ).grid(row=10, column=0, columnspan=3, sticky="ew", pady=(2, 6))

        ttk.Label(controls, text="Host").grid(row=11, column=0, sticky="w")
        ttk.Entry(controls, textvariable=self.ptz_host_var, width=16).grid(
            row=11,
            column=1,
            columnspan=2,
            sticky="ew",
            pady=2,
        )
        ttk.Label(controls, text="Port").grid(row=12, column=0, sticky="w")
        ttk.Entry(controls, textvariable=self.ptz_port_var, width=6).grid(
            row=12,
            column=1,
            columnspan=2,
            sticky="ew",
            pady=2,
        )
        ttk.Label(controls, text="User").grid(row=13, column=0, sticky="w")
        ttk.Entry(controls, textvariable=self.ptz_username_var, width=16).grid(
            row=13,
            column=1,
            columnspan=2,
            sticky="ew",
            pady=2,
        )
        ttk.Label(controls, text="Pass").grid(row=14, column=0, sticky="w")
        ttk.Entry(
            controls,
            textvariable=self.ptz_password_var,
            width=16,
            show="*",
        ).grid(row=14, column=1, columnspan=2, sticky="ew", pady=2)
        ttk.Button(controls, text="Test Stop", command=lambda: self.ptz("stop")).grid(
            row=15,
            column=0,
            columnspan=3,
            sticky="ew",
            pady=(8, 2),
        )
        ttk.Button(controls, text="Quit", command=self.close).grid(
            row=16,
            column=0,
            columnspan=3,
            sticky="ew",
            pady=(14, 2),
        )

        for column in range(3):
            controls.columnconfigure(column, weight=1, minsize=72)

        bottom = ttk.Frame(outer)
        bottom.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        bottom.columnconfigure(0, weight=1)
        ttk.Label(bottom, textvariable=self.status_var).grid(row=0, column=0, sticky="w")
        ttk.Label(bottom, textvariable=self.view_var).grid(row=0, column=1, sticky="e")

    def add_move_button(self, parent, text, action, row, column, columnspan=1):
        """A PTZ button that moves while held and stops when released."""
        button = ttk.Button(parent, text=text)
        button.grid(
            row=row,
            column=column,
            columnspan=columnspan,
            sticky="ew",
            padx=2,
            pady=2,
        )
        button.bind("<ButtonPress-1>", lambda _event: self.on_press(action))
        button.bind("<ButtonRelease-1>", lambda _event: self.on_release(action))
        return button

    def on_press(self, action):
        if self.ptz_profile_var.get() == "digital":
            self.digital_control(action)
            return
        self.cancel_stop_timer()
        self.press_started_at = time.monotonic()
        self.start_physical_ptz(action)

    def on_release(self, _action):
        if self.ptz_profile_var.get() == "digital":
            return
        elapsed_ms = (time.monotonic() - self.press_started_at) * 1000
        remaining_ms = max(0, int(self.args.ptz_hold_ms - elapsed_ms))
        self.stop_timer_id = self.root.after(remaining_ms, self.send_stop)

    def send_stop(self):
        self.stop_timer_id = None
        self.start_physical_ptz("stop")

    def cancel_stop_timer(self):
        if self.stop_timer_id is not None:
            self.root.after_cancel(self.stop_timer_id)
            self.stop_timer_id = None

    def bind_keys(self):
        self.root.bind("<Left>", lambda _event: self.control("left"))
        self.root.bind("<Right>", lambda _event: self.control("right"))
        self.root.bind("<Up>", lambda _event: self.control("up"))
        self.root.bind("<Down>", lambda _event: self.control("down"))
        self.root.bind("+", lambda _event: self.control("zoom_in"))
        self.root.bind("-", lambda _event: self.control("zoom_out"))
        self.root.bind("0", lambda _event: self.reset_view())
        self.root.bind("<Escape>", lambda _event: self.close())

    def resize_video_area(self, event):
        center_x = event.width // 2
        center_y = event.height // 2
        if self.canvas_text_id is not None:
            self.video_canvas.coords(self.canvas_text_id, center_x, center_y)
        if self.canvas_image_id is not None:
            self.video_canvas.coords(self.canvas_image_id, center_x, center_y)

    def set_status(self, text):
        with self.status_lock:
            if self.status_text != text:
                print(text, flush=True)
            self.status_text = text

    def get_status(self):
        with self.status_lock:
            return self.status_text

    def build_ffmpeg_command(self):
        filter_expr = (
            f"fps={self.args.fps},"
            f"scale={self.display_width}:{self.display_height}:"
            "force_original_aspect_ratio=decrease,"
            f"pad={self.display_width}:{self.display_height}:(ow-iw)/2:(oh-ih)/2"
        )
        return [
            self.ffmpeg_path,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-rtsp_transport",
            "tcp",
            "-i",
            self.url_var.get().strip(),
            "-an",
            "-vf",
            filter_expr,
            "-pix_fmt",
            "rgb24",
            "-f",
            "rawvideo",
            "pipe:1",
        ]

    def start_ffmpeg(self):
        if not self.ffmpeg_path:
            self.set_status("ffmpeg.exe was not found.")
            return None

        command = self.build_ffmpeg_command()
        creationflags = 0
        if sys.platform.startswith("win"):
            creationflags = subprocess.CREATE_NO_WINDOW

        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                stdin=subprocess.DEVNULL,
                creationflags=creationflags,
            )
        except OSError as exc:
            self.set_status(f"Could not start FFmpeg: {exc}")
            return None

        with self.process_lock:
            self.process = process

        threading.Thread(target=self.drain_stderr, args=(process,), daemon=True).start()
        self.set_status("FFmpeg started. Waiting for video frames...")
        return process

    def drain_stderr(self, process):
        if process.stderr is None:
            return
        for raw_line in iter(process.stderr.readline, b""):
            if self.stop_event.is_set():
                break
            line = raw_line.decode("utf-8", errors="replace").strip()
            if line:
                print(f"FFmpeg: {line}", flush=True)
                with self.frame_lock:
                    frame_count = self.frame_count
                if frame_count == 0:
                    self.set_status(f"FFmpeg: {line[-160:]}")

    def stop_ffmpeg(self):
        with self.process_lock:
            process = self.process
            self.process = None

        if process is None:
            return
        if process.poll() is not None:
            return

        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

    def reader_loop(self):
        while not self.stop_event.is_set():
            self.reconnect_event.clear()
            process = self.start_ffmpeg()
            if process is None or process.stdout is None:
                time.sleep(2)
                continue

            while not self.stop_event.is_set() and not self.reconnect_event.is_set():
                raw_frame = process.stdout.read(self.frame_size)
                if len(raw_frame) != self.frame_size:
                    break

                with self.frame_lock:
                    self.latest_frame_bytes = raw_frame
                    self.frame_count += 1
                    self.last_frame_at = time.monotonic()
                    frame_count = self.frame_count

                if frame_count == 1 or frame_count % max(1, self.args.fps * 2) == 0:
                    self.set_status(f"Receiving video frames: {frame_count}")

            self.stop_ffmpeg()
            if not self.stop_event.is_set():
                self.set_status("Stream stopped. Reconnecting...")
                time.sleep(1)

    def refresh_video(self):
        frame_bytes = None
        frame_count = 0
        with self.frame_lock:
            if self.latest_frame_bytes is not None:
                frame_bytes = self.latest_frame_bytes
                frame_count = self.frame_count

        if frame_bytes is not None:
            image = Image.frombytes(
                "RGB",
                (self.display_width, self.display_height),
                frame_bytes,
            )
            image = self.prepare_display_image(image)
            self.photo = ImageTk.PhotoImage(image=image)
            canvas_width = max(1, self.video_canvas.winfo_width())
            canvas_height = max(1, self.video_canvas.winfo_height())
            center_x = canvas_width // 2
            center_y = canvas_height // 2
            if self.canvas_image_id is None:
                self.canvas_image_id = self.video_canvas.create_image(
                    center_x,
                    center_y,
                    image=self.photo,
                    anchor="center",
                )
            else:
                self.video_canvas.itemconfigure(self.canvas_image_id, image=self.photo)
                self.video_canvas.coords(self.canvas_image_id, center_x, center_y)
            if self.canvas_text_id is not None:
                self.video_canvas.itemconfigure(self.canvas_text_id, state="hidden")
        elif self.canvas_text_id is not None:
            self.video_canvas.itemconfigure(
                self.canvas_text_id,
                state="normal",
                text=self.get_status(),
            )

        age = ""
        with self.frame_lock:
            if self.last_frame_at is not None:
                age = f" | last frame {time.monotonic() - self.last_frame_at:.1f}s ago"

        self.status_var.set(self.get_status())
        self.view_var.set(
            f"FFmpeg TCP | Frames {frame_count} | Zoom {self.zoom:.2f}x{age}"
        )
        if not self.stop_event.is_set():
            self.root.after(33, self.refresh_video)

    def prepare_display_image(self, image):
        if self.zoom <= 1.0:
            return image

        width, height = image.size
        crop_width = max(1, int(width / self.zoom))
        crop_height = max(1, int(height / self.zoom))
        max_x = max(0, width - crop_width)
        max_y = max(0, height - crop_height)
        center_x = (width / 2) + (self.pan_x * max_x / 2)
        center_y = (height / 2) + (self.pan_y * max_y / 2)
        x1 = int(center_x - crop_width / 2)
        y1 = int(center_y - crop_height / 2)
        x1 = min(max(0, x1), max_x)
        y1 = min(max(0, y1), max_y)
        cropped = image.crop((x1, y1, x1 + crop_width, y1 + crop_height))
        return cropped.resize((width, height), Image.Resampling.BILINEAR)

    def reconnect(self):
        self.set_status("Reconnect requested")
        self.reconnect_event.set()

    def snapshot(self):
        with self.frame_lock:
            frame_bytes = self.latest_frame_bytes

        if frame_bytes is None:
            messagebox.showwarning("Camera", "No camera frame is available yet.")
            return

        image = Image.frombytes("RGB", (self.display_width, self.display_height), frame_bytes)
        image = self.prepare_display_image(image)
        self.snapshot_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = self.snapshot_dir / f"ffmpeg_snapshot_{timestamp}.jpg"
        image.save(output_path, quality=92)
        self.set_status(f"Snapshot saved: {output_path}")

    def control(self, action):
        if self.ptz_profile_var.get() != "digital":
            self.ptz(action)
            return
        self.digital_control(action)

    def digital_control(self, action):
        step = 0.16
        if action == "left":
            self.pan_x = max(-1.0, self.pan_x - step)
        elif action == "right":
            self.pan_x = min(1.0, self.pan_x + step)
        elif action == "up":
            self.pan_y = max(-1.0, self.pan_y - step)
        elif action == "down":
            self.pan_y = min(1.0, self.pan_y + step)
        elif action == "zoom_in":
            self.zoom = min(8.0, self.zoom * 1.25)
        elif action == "zoom_out":
            self.zoom = max(1.0, self.zoom / 1.25)
            if self.zoom == 1.0:
                self.pan_x = 0.0
                self.pan_y = 0.0

    def reset_view(self):
        self.zoom = 1.0
        self.pan_x = 0.0
        self.pan_y = 0.0
        if self.ptz_profile_var.get() == "onvif":
            self.cancel_stop_timer()
            self.start_physical_ptz("home")

    def ptz(self, action):
        profile = self.ptz_profile_var.get()
        if profile == "digital":
            self.digital_control(action)
            return

        self.cancel_stop_timer()
        self.start_physical_ptz(action)
        stop_url = self.ptz_urls.get("stop")
        if action != "stop" and (profile != "custom" or stop_url):
            self.stop_timer_id = self.root.after(self.args.ptz_hold_ms, self.send_stop)

    def get_ptz_settings(self):
        try:
            port = int(self.ptz_port_var.get().strip() or "80")
        except ValueError:
            port = None

        return {
            "profile": self.ptz_profile_var.get(),
            "host": self.ptz_host_var.get().strip(),
            "port": port,
            "username": self.ptz_username_var.get().strip() or None,
            "password": self.ptz_password_var.get(),
        }

    def start_physical_ptz(self, action):
        settings = self.get_ptz_settings()
        threading.Thread(
            target=self.send_physical_ptz,
            args=(action, settings),
            daemon=True,
        ).start()

    def send_physical_ptz(self, action, settings):
        profile = settings["profile"]
        username = settings["username"]
        password = settings["password"]
        self.set_status(f"Sending PTZ command: {action}")
        if profile == "custom":
            url = self.ptz_urls.get(action)
            if not url:
                self.set_status(f"No custom PTZ URL configured for {action}")
                return
            result = send_ptz_urls([url], username=username, password=password)
        else:
            host = settings["host"]
            port = settings["port"]
            if port is None:
                self.set_status("Invalid PTZ port.")
                return

            try:
                result = send_ptz_action(
                    profile=profile,
                    host=host,
                    port=port,
                    action=action,
                    username=username,
                    password=password,
                    speed=self.args.ptz_speed,
                    pan_speed=self.args.ptz_pan_speed,
                    tilt_speed=self.args.ptz_tilt_speed,
                    zoom_speed=self.args.ptz_zoom_speed,
                    onvif_speed=self.args.ptz_onvif_speed,
                    onvif_zoom_speed=self.args.ptz_onvif_zoom_speed,
                    invert_pan=self.args.ptz_invert_pan,
                    invert_tilt=self.args.ptz_invert_tilt,
                )
            except ValueError as exc:
                self.set_status(f"PTZ command not supported by {profile}: {exc}")
                return

        if result.ok:
            self.set_status(f"PTZ command sent: {action} ({result.message})")
        else:
            self.set_status(f"PTZ command failed: {action} ({result.message})")

    def close(self):
        self.cancel_stop_timer()
        if self.ptz_profile_var.get() != "digital":
            # Otherwise a camera still mid-move keeps panning after the window closes.
            self.start_physical_ptz("stop")
        self.stop_event.set()
        self.reconnect_event.set()
        self.stop_ffmpeg()
        self.root.after(100, self.root.destroy)


def main():
    args = parse_args()
    if find_ffmpeg(args.ffmpeg) is None:
        print("ffmpeg.exe was not found. Install FFmpeg or set FFMPEG_PATH.", file=sys.stderr)
        return 1

    root = tk.Tk()
    FfmpegCameraGui(root, args)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
