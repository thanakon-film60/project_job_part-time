import math

from .config import settings

LOCATION_CATEGORY_LABELS = {
    "home": "บ้าน",
    "work": "ที่ทำงาน",
    "hospital": "โรงพยาบาล",
}


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """ระยะทางระหว่างสองพิกัด (กิโลเมตร) ด้วยสูตร Haversine"""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def _is_work_office(office: dict) -> bool:
    """จุดติดตามสถานะอาจไม่ใช่สถานที่ที่อนุญาตให้ออกงาน"""
    return bool(office.get("allow_checkout", True))


def _normalize_location_category(value: object, office_name: str = "") -> str:
    """แปลง category/name ให้เหลือหมวดมาตรฐานสำหรับข้อความแจ้งเตือน"""
    explicit = str(value or "").strip().lower()
    if explicit in ("home", "house", "บ้าน"):
        return "home"
    if explicit in ("hospital", "clinic", "โรงพยาบาล", "โรงบาล", "รพ"):
        return "hospital"
    if explicit in ("work", "office", "workplace", "ที่ทำงาน", "ออฟฟิศ", "บริษัท"):
        return "work"

    text = f"{explicit} {office_name}".lower()
    if any(word in text for word in ("บ้าน", "home", "house")):
        return "home"
    if any(
        word in text
        for word in ("โรงพยาบาล", "โรงบาล", "hospital", "clinic", "bjh", "รพ.")
    ):
        return "hospital"
    return "work"


def location_category(office: dict | None) -> str:
    if not office:
        return "work"
    return _normalize_location_category(
        office.get("category"), str(office.get("name") or "")
    )


def location_category_label(office: dict | None) -> str:
    return LOCATION_CATEGORY_LABELS[location_category(office)]


def office_by_name(name: str | None) -> dict | None:
    """หา config ของสถานที่จากชื่อที่บันทึกไว้ใน checkins.office_name"""
    target = (name or "").strip()
    if not target:
        return None
    for office in settings.offices_list:
        if str(office.get("name") or "").strip() == target:
            return office
    return {"name": target}


def evaluate_location(
    lat: float, lon: float, *, work_only: bool = False
) -> tuple[float, bool, dict]:
    """ตรวจว่าพิกัดที่ส่งมาอยู่ในเขตของสถานที่ใดหรือไม่

    รองรับหลายสถานที่ (ดู OFFICES ใน .env)

    วิธีเลือก: ถ้าอยู่ในเขตของหลายที่พร้อมกัน เลือกที่ "ใกล้ที่สุด"
    ถ้าไม่อยู่ในเขตของที่ไหนเลย ก็คืนที่ที่ใกล้ที่สุดไว้เพื่อบอกว่าห่างเท่าไร

    คืนค่า (ระยะจากสถานที่ที่เลือก กม., อยู่ในเขตหรือไม่, ข้อมูลสถานที่)
    """
    offices = settings.offices_list
    if work_only:
        offices = [office for office in offices if _is_work_office(office)]
        if not offices:
            raise RuntimeError("ยังไม่ได้กำหนดสถานที่ทำงานสำหรับการออกงาน")

    # คำนวณระยะไปทุกที่ แล้วเรียงตาม (อยู่ในเขตก่อน, ระยะใกล้ก่อน)
    scored = []
    for office in offices:
        dist = haversine_km(lat, lon, office["lat"], office["lng"])
        inside = dist <= office["radius_km"]
        scored.append((not inside, dist, office))

    scored.sort(key=lambda x: (x[0], x[1]))
    outside, dist, office = scored[0]
    return dist, (not outside), office


def describe_offices(*, work_only: bool = False) -> str:
    """ข้อความสรุปสถานที่ทั้งหมด ใช้ในข้อความ error ตอนเช็คอินไม่ผ่าน"""
    offices = settings.offices_list
    if work_only:
        offices = [office for office in offices if _is_work_office(office)]
    return ", ".join(
        f"{o['name']} (รัศมี {o['radius_km']} กม.)" for o in offices
    )
