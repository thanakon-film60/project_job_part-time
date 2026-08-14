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

  // พิกัดออฟฟิศ MARDODI (จากลิงก์ Google Maps) — ใช้แสดงผล/ตรวจเบื้องต้นบนเครื่อง
  static const double officeLat = 13.9231953;
  static const double officeLng = 100.5195808;
  static const double geofenceRadiusKm = 2.0;

  // ช่วงเวลาส่งพิกัด GPS ต่อเนื่อง (วินาที)
  static const int pingIntervalSeconds = 60;
}
