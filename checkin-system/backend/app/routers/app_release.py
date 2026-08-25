r"""แจกไฟล์ติดตั้งแอป Flutter (APK) ให้พนักงานโหลดจากหน้าเว็บ

ไฟล์ APK ไม่ได้อยู่ในโฟลเดอร์เว็บ (IIS) เพราะทุกครั้งที่ deploy หน้าเว็บใหม่
สคริปต์จะล้างโฟลเดอร์นั้นทิ้ง — เก็บไว้ใน storage ของ backend แทน แล้วให้
backend เป็นคนเสิร์ฟ ไฟล์จึงอยู่รอดข้าม deploy และไม่ต้อง commit เข้า git

สร้าง/อัปเดตไฟล์ด้วย  deploy\windows-server\build-flutter-apk.ps1

⚠️ สองเส้นทางนี้ "ไม่ต้องล็อกอิน" ตั้งใจให้เปิดจากมือถือ/สแกน QR ได้ทันที
   (ตัวติดตั้งเปล่า ๆ ไม่มีข้อมูลพนักงานอยู่ข้างใน — ต้องล็อกอินในแอปอยู่ดี)
"""

import json
import os
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from ..config import settings

router = APIRouter(prefix="/app", tags=["app"])

APK_DIR = os.path.join(settings.storage_dir, "app")
APK_NAME = "thanakon-checkin.apk"
APK_PATH = os.path.join(APK_DIR, APK_NAME)
META_PATH = os.path.join(APK_DIR, "release.json")

# Android จะไม่ยอมติดตั้งถ้า content-type ไม่ใช่อันนี้ (บางเบราว์เซอร์เซฟเป็น .zip)
APK_MEDIA_TYPE = "application/vnd.android.package-archive"


def _meta() -> dict:
    """ข้อมูลเวอร์ชันที่สคริปต์ build เขียนไว้ — ไม่มีก็ไม่เป็นไร"""
    try:
        # utf-8-sig: PowerShell 5.1 (Set-Content -Encoding UTF8) ใส่ BOM ไว้หน้าไฟล์
        # ถ้าอ่านแบบ utf-8 เฉย ๆ จะ decode ไม่ผ่าน แล้วเวอร์ชันจะหายไปจากหน้าเว็บ
        with open(META_PATH, "r", encoding="utf-8-sig") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


@router.get("/info")
def app_info():
    """หน้าเว็บใช้เช็กว่ามีไฟล์ให้โหลดไหม + โชว์ขนาด/วันที่ build"""
    if not os.path.isfile(APK_PATH):
        return {"available": False}

    stat = os.stat(APK_PATH)
    meta = _meta()
    return {
        "available": True,
        "filename": APK_NAME,
        "download_url": "/app/download",
        "size_bytes": stat.st_size,
        # เวลาที่ไฟล์ถูกวางไว้ (UTC) — ฝั่งเว็บแปลงเป็นเวลาไทยเอง
        "built_at": meta.get("built_at")
        or datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        "version": meta.get("version") or "",
        "min_android": meta.get("min_android") or "",
    }


@router.get("/download")
def app_download():
    if not os.path.isfile(APK_PATH):
        raise HTTPException(
            status_code=404,
            # ใส่ r"" เพราะ \b ในเส้นทางไฟล์คือตัวอักษร backspace ถ้าไม่ใส่
            detail=r"ยังไม่มีไฟล์ติดตั้ง — รัน deploy\windows-server\build-flutter-apk.ps1 ก่อน",
        )

    version = _meta().get("version") or ""
    # ใส่เวอร์ชันในชื่อไฟล์ที่โหลด จะได้ไม่ทับกับตัวเก่าในเครื่องพนักงาน
    filename = f"thanakon-checkin-{version}.apk" if version else APK_NAME
    return FileResponse(APK_PATH, media_type=APK_MEDIA_TYPE, filename=filename)
