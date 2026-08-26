import '../config.dart';
import 'json.dart';

/// สถานะความสดของพิกัดล่าสุด — backend เป็นคนตัดสินให้ (locations.py)
/// แอปไม่คำนวณเอง เพราะนาฬิกาของมือถือแต่ละเครื่องเชื่อไม่ได้
enum LiveStatus {
  /// ยังส่งพิกัดอยู่ (ไม่เกิน 5 นาที)
  online,

  /// เงียบไปสักพัก (5–30 นาที)
  stale,

  /// ขาดการติดต่อ (เกิน 30 นาที)
  offline,

  /// ไม่เคยส่งพิกัดมาเลย — แอปยังไม่ได้ติดตั้ง/ไม่เคยล็อกอิน
  noData;

  static LiveStatus parse(Object? value) {
    switch (value?.toString()) {
      case 'online':
        return LiveStatus.online;
      case 'stale':
        return LiveStatus.stale;
      case 'offline':
        return LiveStatus.offline;
      default:
        return LiveStatus.noData;
    }
  }

  String get label {
    switch (this) {
      case LiveStatus.online:
        return 'กำลังส่งตำแหน่ง';
      case LiveStatus.stale:
        return 'ไม่อัปเดตสักพัก';
      case LiveStatus.offline:
        return 'ขาดการติดต่อ';
      case LiveStatus.noData:
        return 'ไม่มีข้อมูล';
    }
  }

  /// ลำดับการเรียง — คนที่ยังส่งพิกัดอยู่ต้องขึ้นก่อน (ตรงกับ backend)
  int get order => index;
}

/// ตำแหน่งล่าสุดของพนักงาน 1 คน (/locations/live)
class LiveLocation {
  final int employeeId;
  final String employeeCode;
  final String fullName;
  final bool isManager;

  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final bool? withinGeofence;
  final String? officeName;

  final DateTime? timestamp;

  /// อายุของพิกัดคิดจากฝั่งเซิร์ฟเวอร์ — ไม่ขึ้นกับนาฬิกาของมือถือ
  final int? secondsAgo;
  final LiveStatus status;

  const LiveLocation({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.isManager,
    required this.status,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.withinGeofence,
    this.officeName,
    this.timestamp,
    this.secondsAgo,
  });

  bool get hasPosition => latitude != null && longitude != null;

  /// อยู่ที่ไหน — ตรรกะเดียวกับ describeWhere ใน frontend/src/lib/attendance.js
  ///
  /// อยู่ในเขตบ้าน = "อยู่บ้าน" ไม่ใช่ "อยู่ในเขตที่ทำงาน"
  String get whereText {
    final place = officeName ?? 'ที่ทำงาน';
    if (withinGeofence == true) {
      return Office.isHomeLabel(officeName) ? 'อยู่บ้าน' : 'อยู่ในเขต $place';
    }
    final distance =
        distanceKm == null ? '-' : '${distanceKm!.toStringAsFixed(2)} กม.';
    return 'นอกเขต ห่าง $distance จาก $place';
  }

  /// แบบสั้นสำหรับรายชื่อ (describeWhereShort)
  String get whereShortText {
    final place = officeName ?? 'ที่ทำงาน';
    if (withinGeofence == true) {
      return Office.isHomeLabel(officeName) ? 'อยู่บ้าน' : 'ในเขต $place';
    }
    final distance =
        distanceKm == null ? '-' : '${distanceKm!.toStringAsFixed(2)} กม.';
    return 'นอกเขต ห่าง $distance';
  }

  /// "เมื่อสักครู่ / 12 นาทีที่แล้ว / 2 ชม. 5 นาทีที่แล้ว"
  /// (formatAge ใน frontend/src/pages/LiveMapPage.jsx)
  String get ageText {
    final seconds = secondsAgo;
    if (seconds == null) return 'ไม่เคยส่งพิกัด';
    if (seconds < 60) return 'เมื่อสักครู่';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes นาทีที่แล้ว';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours ชม. ${minutes % 60} นาทีที่แล้ว';
    return '${hours ~/ 24} วันที่แล้ว';
  }

  factory LiveLocation.fromJson(Map<String, dynamic> json) {
    return LiveLocation(
      employeeId: asInt(json['employee_id']),
      employeeCode: asText(json['employee_code']) ?? '-',
      fullName: asText(json['full_name']) ?? '-',
      isManager: asBool(json['is_manager']),
      status: LiveStatus.parse(json['status']),
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      distanceKm: asDouble(json['distance_km']),
      withinGeofence:
          json['within_geofence'] is bool ? json['within_geofence'] as bool : null,
      officeName: asText(json['office_name']),
      timestamp: parseServerDateTime(json['timestamp']),
      secondsAgo: json['seconds_ago'] == null ? null : asInt(json['seconds_ago']),
    );
  }
}

/// ภาพรวมตำแหน่งพนักงานทุกคน ณ เวลาหนึ่ง
class LiveLocationsSnapshot {
  final DateTime? serverTime;
  final List<LiveLocation> employees;

  const LiveLocationsSnapshot({
    required this.employees,
    this.serverTime,
  });

  /// นับจำนวนคนในแต่ละสถานะ ใช้ทำแถบสรุปด้านบน
  Map<LiveStatus, int> get counts {
    final result = {for (final status in LiveStatus.values) status: 0};
    for (final employee in employees) {
      result[employee.status] = (result[employee.status] ?? 0) + 1;
    }
    return result;
  }

  List<LiveLocation> get located =>
      employees.where((employee) => employee.hasPosition).toList(growable: false);

  factory LiveLocationsSnapshot.fromJson(Map<String, dynamic> json) {
    return LiveLocationsSnapshot(
      serverTime: parseServerDateTime(json['server_time']),
      employees: mapList(json['employees'], LiveLocation.fromJson),
    );
  }
}

/// จุดหนึ่งบนเส้นทางย้อนหลัง (/locations/trail/{employee_id})
class TrailPoint {
  final DateTime? timestamp;
  final double latitude;
  final double longitude;
  final bool withinGeofence;
  final String? officeName;

  const TrailPoint({
    required this.latitude,
    required this.longitude,
    required this.withinGeofence,
    this.timestamp,
    this.officeName,
  });

  factory TrailPoint.fromJson(Map<String, dynamic> json) {
    return TrailPoint(
      latitude: asDouble(json['latitude']) ?? 0,
      longitude: asDouble(json['longitude']) ?? 0,
      withinGeofence: asBool(json['within_geofence']),
      timestamp: parseServerDateTime(json['timestamp']),
      officeName: asText(json['office_name']),
    );
  }
}
