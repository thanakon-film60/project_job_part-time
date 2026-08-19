class Config {
  // ---------------------------------------------------------------
  // production: ผ่าน Cloudflare Tunnel -> IIS :80 -> backend
  // Cloudflare จัดการ HTTPS/SSL ให้อัตโนมัติ เหมาะกับ iOS App Transport Security
  // ที่บังคับ HTTPS (ดู deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md)
  //
  // เรียก API ได้ตรง ๆ ไม่มี /api นำหน้า เช่น
  //   POST https://thanakronpart-time.com/auth/login
  //   GET  https://thanakronpart-time.com/reports/calendar
  //
  // ตอนพัฒนาบนเครื่องตัวเอง ให้สลับไปใช้บรรทัดที่คอมเมนต์ไว้แทน:
  //   Android emulator : http://10.0.2.2:8002
  //   iOS simulator    : http://localhost:8002
  // ---------------------------------------------------------------
  static const String apiBase = "https://thanakronpart-time.com";
  // static const String apiBase = "http://10.0.2.2:8002";

  // ---------------------------------------------------------------
  // สถานที่ที่เช็คอินได้ (ใช้แสดงผล/ตรวจเบื้องต้นบนเครื่องเท่านั้น)
  //
  // ⚠️ ตัวตัดสินจริงคือ backend — ถ้าแก้รายการนี้ต้องแก้ OFFICES ใน backend/.env ให้ตรงกันด้วย
  // ---------------------------------------------------------------
  static const List<Office> offices = [
    Office(name: "MARDODI", lat: 13.9231953, lng: 100.5195808, radiusKm: 2.0),
    Office(name: "BJH Bangkok", lat: 13.8918358, lng: 100.563443, radiusKm: 1.0),
    Office(name: "ถึงบ้านแล้ว", lat: 13.8865664, lng: 100.5066278, radiusKm: 0.2),
  ];

  // ของเดิม เก็บไว้ให้โค้ดส่วนที่ยังอ้างถึงอยู่ไม่พัง = สถานที่แรกในรายการ
  static double get officeLat => offices.first.lat;
  static double get officeLng => offices.first.lng;
  static double get geofenceRadiusKm => offices.first.radiusKm;

  // ช่วงเวลาส่งพิกัด GPS ต่อเนื่อง (วินาที)
  static const int pingIntervalSeconds = 60;
}


/// สถานที่ที่เช็คอินได้ 1 แห่ง
class Office {
  final String name;
  final double lat;
  final double lng;
  final double radiusKm;

  const Office({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
  });
}
