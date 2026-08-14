class Config {
  // เปลี่ยนเป็น IP/โดเมนของ backend จริง
  // Android emulator ใช้ 10.0.2.2 แทน localhost
  static const String apiBase = "http://10.0.2.2:8000";

  // พิกัดออฟฟิศ MARDODI (จากลิงก์ Google Maps) — ใช้แสดงผล/ตรวจเบื้องต้นบนเครื่อง
  static const double officeLat = 13.9231953;
  static const double officeLng = 100.5195808;
  static const double geofenceRadiusKm = 2.0;

  // ช่วงเวลาส่งพิกัด GPS ต่อเนื่อง (วินาที)
  static const int pingIntervalSeconds = 60;
}
