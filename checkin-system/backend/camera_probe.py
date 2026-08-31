import argparse
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

from PIL import Image, ImageStat

from camera_view import DEFAULT_CAMERA_URL


DEFAULT_FFMPEG_PATH = r"C:\ProgramData\chocolatey\bin\ffmpeg.exe"


def parse_args():
    parser = argparse.ArgumentParser(description="Probe an RTSP camera connection.")
    parser.add_argument("--url", default=DEFAULT_CAMERA_URL, help="RTSP camera URL.")
    parser.add_argument(
        "--snapshot",
        default="storage/camera-probe.jpg",
        help="Snapshot path used to verify the decoded image.",
    )
    parser.add_argument(
        "--seconds",
        type=float,
        default=5.0,
        help="How long FFmpeg should decode the stream after snapshot verification.",
    )
    parser.add_argument(
        "--socket-timeout",
        type=float,
        default=3.0,
        help="TCP socket timeout in seconds.",
    )
    parser.add_argument(
        "--ffmpeg",
        default=None,
        help="Path to ffmpeg.exe. Default: auto-detect.",
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


def test_socket(url, timeout):
    parsed = urlparse(url)
    host = parsed.hostname
    port = parsed.port or (554 if parsed.scheme == "rtsp" else 80)
    if not host:
        return False, "No host found in URL"

    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True, f"TCP port open: {host}:{port}"
    except OSError as exc:
        return False, f"TCP port failed: {host}:{port} ({exc})"


def run_command(command, timeout):
    creationflags = 0
    if sys.platform.startswith("win"):
        creationflags = subprocess.CREATE_NO_WINDOW

    return subprocess.run(
        command,
        capture_output=True,
        creationflags=creationflags,
        text=True,
        timeout=timeout,
    )


def verify_snapshot(path):
    image = Image.open(path).convert("RGB")
    width, height = image.size
    stats = ImageStat.Stat(image)
    average_stddev = sum(stats.stddev) / len(stats.stddev)
    return width, height, average_stddev


def main():
    args = parse_args()

    ok, message = test_socket(args.url, args.socket_timeout)
    print(message)
    if not ok:
        return 1

    ffmpeg_path = find_ffmpeg(args.ffmpeg)
    if ffmpeg_path is None:
        print("ffmpeg.exe was not found.")
        return 1
    print(f"FFmpeg: {ffmpeg_path}")

    snapshot_path = Path(args.snapshot)
    snapshot_path.parent.mkdir(parents=True, exist_ok=True)
    snapshot_command = [
        ffmpeg_path,
        "-y",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-rtsp_transport",
        "tcp",
        "-i",
        args.url,
        "-frames:v",
        "1",
        "-update",
        "1",
        str(snapshot_path),
    ]
    print(f"Saving decoded snapshot: {snapshot_path}")
    snapshot_result = run_command(snapshot_command, timeout=45)
    if snapshot_result.stdout.strip():
        print(snapshot_result.stdout.strip())
    if snapshot_result.stderr.strip():
        print(snapshot_result.stderr.strip())
    if snapshot_result.returncode != 0:
        print("FFmpeg snapshot failed.")
        return 1

    width, height, average_stddev = verify_snapshot(snapshot_path)
    print(f"Snapshot OK: {width}x{height}, image variation {average_stddev:.2f}")
    if average_stddev < 10:
        print("Decoded image looks flat or corrupted. Try another RTSP stream path.")
        return 1

    stream_command = [
        ffmpeg_path,
        "-hide_banner",
        "-loglevel",
        "error",
        "-rtsp_transport",
        "tcp",
        "-i",
        args.url,
        "-t",
        str(args.seconds),
        "-an",
        "-f",
        "null",
        "-",
    ]
    print(f"Decoding stream for {args.seconds:.1f} seconds...")
    stream_result = run_command(stream_command, timeout=args.seconds + 30)
    if stream_result.stderr.strip():
        print(stream_result.stderr.strip())
    if stream_result.returncode != 0:
        print("FFmpeg stream decode failed.")
        return 1

    print("Camera connection OK with FFmpeg.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
