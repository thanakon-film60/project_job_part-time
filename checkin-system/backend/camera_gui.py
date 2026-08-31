import argparse
import os
import sys
import threading
import time
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk
from urllib.error import URLError
from urllib.request import Request, urlopen

import cv2
from PIL import Image, ImageTk

from camera_view import DEFAULT_CAMERA_URL, connect_capture


PTZ_ACTIONS = ("left", "right", "up", "down", "zoom_in", "zoom_out", "stop")


def parse_args():
    parser = argparse.ArgumentParser(description="Desktop GUI for an RTSP IP camera.")
    parser.add_argument(
        "--url",
        default=os.environ.get("CAMERA_URL", DEFAULT_CAMERA_URL),
        help=f"RTSP camera URL. Default: {DEFAULT_CAMERA_URL}",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=960,
        help="Video display width.",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=540,
        help="Video display height.",
    )
    parser.add_argument(
        "--snapshot-dir",
        default="storage/camera-snapshots",
        help="Directory for saved snapshots.",
    )
    parser.add_argument(
        "--ptz-mode",
        choices=("digital", "http"),
        default=os.environ.get("CAMERA_PTZ_MODE", "digital").lower(),
        help="digital crops the stream. http sends configured PTZ command URLs.",
    )

    for action in PTZ_ACTIONS:
        option = action.replace("_", "-")
        parser.add_argument(
            f"--ptz-{option}-url",
            default=os.environ.get(f"CAMERA_PTZ_{action.upper()}_URL"),
            help=f"HTTP GET URL for PTZ action: {action}",
        )

    return parser.parse_args()


class CameraGui:
    def __init__(self, root, args):
        self.root = root
        self.args = args
        self.video_width = args.width
        self.video_height = args.height
        self.snapshot_dir = Path(args.snapshot_dir)
        self.ptz_mode = args.ptz_mode
        self.ptz_urls = {
            action: getattr(args, f"ptz_{action}_url") for action in PTZ_ACTIONS
        }

        self.frame_lock = threading.Lock()
        self.status_lock = threading.Lock()
        self.url_lock = threading.Lock()
        self.latest_frame = None
        self.status_text = "Starting"
        self.printed_status_text = None
        self.camera_url = args.url
        self.frame_count = 0
        self.last_frame_status_at = 0.0

        self.stop_event = threading.Event()
        self.reconnect_event = threading.Event()

        self.zoom = 1.0
        self.pan_x = 0.0
        self.pan_y = 0.0

        self.photo = None
        self.url_var = tk.StringVar(value=args.url)

        self.build_ui()
        self.bind_keys()

        self.capture_thread = threading.Thread(target=self.capture_loop, daemon=True)
        self.capture_thread.start()

        self.root.after(30, self.refresh_video)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def build_ui(self):
        self.root.title("IP Camera GUI")
        self.root.geometry(f"{max(1160, self.video_width + 190)}x{self.video_height + 170}")
        self.root.minsize(900, 620)

        outer = ttk.Frame(self.root, padding=12)
        outer.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(1, weight=1)

        top = ttk.Frame(outer)
        top.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 10))
        top.columnconfigure(1, weight=1)

        ttk.Label(top, text="RTSP URL").grid(row=0, column=0, sticky="w")
        url_entry = ttk.Entry(top, textvariable=self.url_var)
        url_entry.grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(top, text="Reconnect", command=self.reconnect).grid(
            row=0, column=2, padx=(0, 8)
        )
        ttk.Button(top, text="Snapshot", command=self.snapshot).grid(row=0, column=3)

        self.video_canvas = tk.Canvas(
            outer,
            bg="#111111",
            width=self.video_width,
            height=self.video_height,
            bd=0,
            highlightthickness=0,
        )
        self.video_canvas.grid(row=1, column=0, sticky="nsew")
        self.video_canvas.bind("<Configure>", self.resize_video_area)
        self.canvas_image_id = None
        self.canvas_text_id = self.video_canvas.create_text(
            self.video_width // 2,
            self.video_height // 2,
            fill="#d7dde6",
            text="Waiting for camera video...",
        )

        controls = ttk.Frame(outer, padding=(12, 0, 0, 0))
        controls.grid(row=1, column=1, sticky="ns")

        ttk.Label(controls, text="Move").grid(row=0, column=0, columnspan=3, pady=(0, 8))
        ttk.Button(controls, text="Up", command=lambda: self.control("up")).grid(
            row=1, column=1, sticky="ew", pady=2
        )
        ttk.Button(controls, text="Left", command=lambda: self.control("left")).grid(
            row=2, column=0, sticky="ew", padx=2, pady=2
        )
        ttk.Button(controls, text="Reset", command=self.reset_view).grid(
            row=2, column=1, sticky="ew", padx=2, pady=2
        )
        ttk.Button(controls, text="Right", command=lambda: self.control("right")).grid(
            row=2, column=2, sticky="ew", padx=2, pady=2
        )
        ttk.Button(controls, text="Down", command=lambda: self.control("down")).grid(
            row=3, column=1, sticky="ew", pady=2
        )

        ttk.Separator(controls).grid(
            row=4, column=0, columnspan=3, sticky="ew", pady=14
        )
        ttk.Button(controls, text="Zoom +", command=lambda: self.control("zoom_in")).grid(
            row=5, column=0, columnspan=3, sticky="ew", pady=2
        )
        ttk.Button(
            controls, text="Zoom -", command=lambda: self.control("zoom_out")
        ).grid(row=6, column=0, columnspan=3, sticky="ew", pady=2)
        ttk.Button(controls, text="Quit", command=self.close).grid(
            row=7, column=0, columnspan=3, sticky="ew", pady=(14, 2)
        )

        for column in range(3):
            controls.columnconfigure(column, weight=1, minsize=64)

        bottom = ttk.Frame(outer)
        bottom.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        bottom.columnconfigure(0, weight=1)
        self.status_label = ttk.Label(bottom, text="Starting")
        self.status_label.grid(row=0, column=0, sticky="w")
        self.view_label = ttk.Label(bottom, text="")
        self.view_label.grid(row=0, column=1, sticky="e")

    def bind_keys(self):
        self.root.bind("<Left>", lambda _event: self.control("left"))
        self.root.bind("<Right>", lambda _event: self.control("right"))
        self.root.bind("<Up>", lambda _event: self.control("up"))
        self.root.bind("<Down>", lambda _event: self.control("down"))
        self.root.bind("+", lambda _event: self.control("zoom_in"))
        self.root.bind("-", lambda _event: self.control("zoom_out"))
        self.root.bind("0", lambda _event: self.reset_view())
        self.root.bind("<Escape>", lambda _event: self.close())

    def set_status(self, text):
        with self.status_lock:
            self.status_text = text
            if text != self.printed_status_text:
                self.printed_status_text = text
                print(text, flush=True)

    def get_status(self):
        with self.status_lock:
            return self.status_text

    def get_camera_url(self):
        with self.url_lock:
            return self.camera_url

    def set_camera_url(self, url):
        with self.url_lock:
            self.camera_url = url

    def resize_video_area(self, event):
        self.video_width = max(1, event.width)
        self.video_height = max(1, event.height)
        center_x = self.video_width // 2
        center_y = self.video_height // 2
        if self.canvas_text_id is not None:
            self.video_canvas.coords(self.canvas_text_id, center_x, center_y)
        if self.canvas_image_id is not None:
            self.video_canvas.coords(self.canvas_image_id, center_x, center_y)

    def capture_loop(self):
        capture = None
        while not self.stop_event.is_set():
            if self.reconnect_event.is_set():
                if capture is not None:
                    capture.release()
                capture = None
                self.reconnect_event.clear()

            if capture is None or not capture.isOpened():
                url = self.get_camera_url()
                self.set_status(f"Connecting: {url}")
                capture, first_frame = connect_capture(url, frame_retries=60)
                if capture is None:
                    self.set_status("Connection failed or no video frame. Retrying...")
                    time.sleep(2)
                    continue
                self.store_frame(first_frame)

            ok, frame = capture.read()
            if ok and frame is not None and frame.size > 0:
                self.store_frame(frame)
            else:
                self.set_status("Frame read failed. Reconnecting...")
                if capture is not None:
                    capture.release()
                capture = None
                time.sleep(1)

        if capture is not None:
            capture.release()

    def store_frame(self, frame):
        with self.frame_lock:
            self.latest_frame = frame
            self.frame_count += 1
            frame_count = self.frame_count

        now = time.monotonic()
        if frame_count == 1 or now - self.last_frame_status_at >= 2:
            height, width = frame.shape[:2]
            self.set_status(f"Connected - receiving video {width}x{height}")
            self.last_frame_status_at = now

    def refresh_video(self):
        frame = None
        with self.frame_lock:
            if self.latest_frame is not None:
                frame = self.latest_frame.copy()

        if frame is not None:
            display_frame = self.prepare_display_frame(frame)
            self.photo = self.frame_to_photo(display_frame)
            center_x = self.video_width // 2
            center_y = self.video_height // 2
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

        self.status_label.configure(text=self.get_status())
        mode_label = "Digital PTZ" if self.ptz_mode == "digital" else "HTTP PTZ"
        self.view_label.configure(
            text=f"{mode_label} | Zoom {self.zoom:.2f}x | X {self.pan_x:.2f} Y {self.pan_y:.2f}"
        )

        if not self.stop_event.is_set():
            self.root.after(30, self.refresh_video)

    def prepare_display_frame(self, frame):
        height, width = frame.shape[:2]
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

        cropped = frame[y1 : y1 + crop_height, x1 : x1 + crop_width]
        scale = min(
            self.video_width / max(1, cropped.shape[1]),
            self.video_height / max(1, cropped.shape[0]),
        )
        resized_width = max(1, int(cropped.shape[1] * scale))
        resized_height = max(1, int(cropped.shape[0] * scale))
        resized = cv2.resize(cropped, (resized_width, resized_height))

        top = (self.video_height - resized_height) // 2
        bottom = self.video_height - resized_height - top
        left = (self.video_width - resized_width) // 2
        right = self.video_width - resized_width - left
        return cv2.copyMakeBorder(
            resized,
            top,
            bottom,
            left,
            right,
            cv2.BORDER_CONSTANT,
            value=(17, 17, 17),
        )

    def frame_to_photo(self, frame):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb)
        return ImageTk.PhotoImage(image=image)

    def reconnect(self):
        url = self.url_var.get().strip()
        if not url:
            messagebox.showwarning("Camera", "Please enter an RTSP URL.")
            return
        self.set_camera_url(url)
        self.set_status("Reconnect requested")
        self.reconnect_event.set()

    def snapshot(self):
        with self.frame_lock:
            frame = None if self.latest_frame is None else self.latest_frame.copy()

        if frame is None:
            messagebox.showwarning("Camera", "No camera frame is available yet.")
            return

        self.snapshot_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = self.snapshot_dir / f"snapshot_{timestamp}.jpg"
        if not cv2.imwrite(str(output_path), frame):
            messagebox.showerror("Camera", f"Could not save snapshot: {output_path}")
            return

        self.set_status(f"Snapshot saved: {output_path}")

    def control(self, action):
        if self.ptz_mode == "http" and self.ptz_urls.get(action):
            self.send_http_ptz(action)
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

    def send_http_ptz(self, action):
        url = self.ptz_urls[action]
        thread = threading.Thread(
            target=self.send_http_command,
            args=(action, url),
            daemon=True,
        )
        thread.start()

        stop_url = self.ptz_urls.get("stop")
        if action != "stop" and stop_url:
            self.root.after(
                350,
                lambda: threading.Thread(
                    target=self.send_http_command,
                    args=("stop", stop_url),
                    daemon=True,
                ).start(),
            )

    def send_http_command(self, action, url):
        self.set_status(f"Sending PTZ command: {action}")
        try:
            request = Request(url, headers={"User-Agent": "camera-gui/1.0"})
            with urlopen(request, timeout=2) as response:
                response.read(256)
            self.set_status(f"PTZ command sent: {action}")
        except (OSError, URLError) as exc:
            self.set_status(f"PTZ command failed: {exc}")

    def close(self):
        self.stop_event.set()
        self.reconnect_event.set()
        self.root.after(100, self.root.destroy)


def main():
    args = parse_args()
    root = tk.Tk()
    CameraGui(root, args)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
