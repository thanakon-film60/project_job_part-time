import argparse
import os
import sys
import time
from pathlib import Path

import cv2


DEFAULT_CAMERA_URL = "rtsp://192.168.1.101:554"
DEFAULT_CAPTURE_OPTIONS = "rtsp_transport;tcp|stimeout;5000000|max_delay;500000"


def parse_args():
    parser = argparse.ArgumentParser(description="View or test an RTSP IP camera.")
    parser.add_argument(
        "--url",
        default=os.environ.get("CAMERA_URL", DEFAULT_CAMERA_URL),
        help=f"RTSP camera URL. Default: {DEFAULT_CAMERA_URL}",
    )
    parser.add_argument(
        "--snapshot",
        help="Save one frame to this path, then exit unless --show is also used.",
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="Show the live camera window. This is the default when --snapshot is not set.",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=60,
        help="Frame read attempts before giving up in snapshot mode.",
    )
    return parser.parse_args()


def open_capture(url):
    os.environ.setdefault("OPENCV_FFMPEG_CAPTURE_OPTIONS", DEFAULT_CAPTURE_OPTIONS)

    capture = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
    if capture.isOpened():
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        return capture

    capture.release()
    capture = cv2.VideoCapture(url)
    if capture.isOpened():
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return capture


def read_frame(capture, retries, delay_seconds=0.1):
    for _ in range(retries):
        ok, frame = capture.read()
        if ok and frame is not None and frame.size > 0:
            return frame
        time.sleep(delay_seconds)
    return None


def connect_capture(url, frame_retries=60, delay_seconds=0.1):
    capture = open_capture(url)
    if not capture.isOpened():
        capture.release()
        return None, None

    first_frame = read_frame(capture, frame_retries, delay_seconds)
    if first_frame is None:
        capture.release()
        return None, None

    return capture, first_frame


def save_snapshot(frame, output_path):
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(path), frame):
        raise RuntimeError(f"Could not save snapshot to {path}")
    print(f"Snapshot saved: {path}")


def show_live(url, capture, first_frame=None):
    window_name = "IP Camera - press q or Esc to quit"
    print(f"Connected: {url}")
    print("Press q or Esc to quit.")
    next_frame = first_frame

    try:
        while True:
            if next_frame is None:
                ok, frame = capture.read()
            else:
                ok, frame = True, next_frame
                next_frame = None

            if not ok or frame is None:
                print("Frame read failed. Reconnecting...")
                capture.release()
                time.sleep(1)
                capture, next_frame = connect_capture(url)
                if capture is None:
                    print("Reconnect failed. Retrying...")
                    time.sleep(1)
                continue

            cv2.imshow(window_name, frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
    finally:
        capture.release()
        cv2.destroyAllWindows()


def main():
    args = parse_args()
    should_show = args.show or not args.snapshot

    print(f"Opening camera: {args.url}")
    capture, first_frame = connect_capture(args.url, args.retries)
    if capture is None:
        print("Could not open the camera and read a video frame.")
        print("Check that VLC can open the same RTSP URL and that the camera is online.")
        return 1

    if args.snapshot:
        save_snapshot(first_frame, args.snapshot)

    if should_show:
        show_live(args.url, capture, first_frame)
    else:
        capture.release()

    return 0


if __name__ == "__main__":
    sys.exit(main())
