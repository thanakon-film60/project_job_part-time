import math

from .config import settings


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


def evaluate_location(lat: float, lon: float) -> tuple[float, bool]:
    """คืน (ระยะจากออฟฟิศ กม., อยู่ในเขตหรือไม่)"""
    dist = haversine_km(lat, lon, settings.office_lat, settings.office_lng)
    return dist, dist <= settings.geofence_radius_km
