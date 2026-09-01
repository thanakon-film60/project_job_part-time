import '../config.dart';
import '../models/employee.dart';
import '../models/live_location.dart';
import '../models/team_calendar.dart';
import 'api_service.dart';

/// คีย์วันที่แบบ YYYY-MM-DD ตามเวลาไทย — ตรงกับคีย์ที่ /reports/team-calendar ส่งมา
String thaiDateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// สถานะของ "วันนี้" ตัดสินจากการลงเวลาของวันนั้น
enum DutyState {
  /// ลงเวลาที่ทำงาน (หรือนอกเขต) แล้ว = มาทำงาน
  working,

  /// วันนั้นมีแต่การลงเวลาที่บ้าน — ไม่นับว่ามาทำงาน (home_only ของ backend)
  home,

  /// ยังไม่มีการลงเวลาเลย = ยังไม่ได้ยืนยันตัวตนของวันนี้
  absent;

  String get label {
    switch (this) {
      case DutyState.working:
        return 'ลงเวลาแล้ว';
      case DutyState.home:
        return 'อยู่บ้าน';
      case DutyState.absent:
        return 'ยังไม่ลงเวลา';
    }
  }

  /// ลำดับการเรียงในรายชื่อ — คนที่ยังไม่ลงเวลาขึ้นก่อน เพราะเป็นเรื่องที่ต้องตามต่อ
  int get order {
    switch (this) {
      case DutyState.absent:
        return 0;
      case DutyState.home:
        return 1;
      case DutyState.working:
        return 2;
    }
  }
}

/// พนักงาน 1 คนในมุมของหัวหน้า
///
/// รวมสามเส้นที่แยกกันอยู่ให้เป็นก้อนเดียว: แฟ้มประวัติ (/reports/employees)
/// การลงเวลาของวันนี้ (/reports/team-calendar) และพิกัดล่าสุด (/locations/live)
class TeamMember {
  final EmployeeProfile profile;

  /// สรุปการลงเวลาของวันนี้ — null = วันนี้ยังไม่ลงเวลาเลย
  final TeamCalendarPerson? today;

  /// พิกัดล่าสุดที่แอปของพนักงานส่งมา — null = ไม่มีข้อมูลจากเส้นติดตาม
  final LiveLocation? live;

  /// เคยลงทะเบียนใบหน้าอ้างอิงไว้แล้วหรือยัง — ไม่เคยลง = สแกนลงเวลาไม่ได้เลย
  final bool faceEnrolled;

  const TeamMember({
    required this.profile,
    required this.faceEnrolled,
    this.today,
    this.live,
  });

  int get id => profile.id;
  String get fullName => profile.fullName;
  String get employeeCode => profile.employeeCode;

  /// ตัวอักษรแรกของชื่อ ใช้ทำ avatar ตอนที่ยังไม่มีรูปใบหน้า
  String get initial {
    final name = fullName.trim();
    return name.isEmpty ? '?' : name.substring(0, 1);
  }

  bool get checkedIn => today != null;

  DutyState get duty {
    final person = today;
    if (person == null) return DutyState.absent;
    return person.homeOnly ? DutyState.home : DutyState.working;
  }

  DateTime? get firstIn => today?.firstIn;
  DateTime? get lastOut => today?.lastOut;

  /// ป้ายสถานที่ของวันนี้ เรียงมาแล้วจาก backend (ที่ทำงานก่อน แล้วค่อยบ้าน)
  List<String> get locations => today?.locations ?? const [];

  LiveStatus get liveStatus => live?.status ?? LiveStatus.noData;

  /// "ในเขต MARDODI" / "นอกเขต ห่าง 3.20 กม." — null เมื่อยังไม่เคยส่งพิกัดมาเลย
  String? get whereText {
    final position = live;
    if (position == null || !position.hasPosition) return null;
    return position.whereShortText;
  }

  /// "เมื่อสักครู่ / 12 นาทีที่แล้ว" ของพิกัดล่าสุด
  String get ageText => live?.ageText ?? 'ไม่เคยส่งพิกัด';
}

/// ภาพรวมทีมของวันนี้ — ก้อนข้อมูลที่แท็บภาพรวมและแท็บข้อมูลพนักงานใช้ร่วมกัน
///
/// สองแท็บนี้ตอบคำถามเดียวกันคนละมุม (สรุปทั้งทีม vs. เจาะรายคน) ถ้าต่างคน
/// ต่างรวมข้อมูลเอง วันหนึ่งตัวเลขสองหน้าจะไม่ตรงกัน จึงรวมไว้ที่เดียว
class TeamStatus {
  /// วันไทยที่สรุปก้อนนี้อ้างถึง (เที่ยงคืนตรง)
  final DateTime day;

  /// พนักงานทั่วไปทุกคน เรียงคนที่ยังไม่ลงเวลาขึ้นก่อน แล้วค่อยตามชื่อ
  ///
  /// ไม่รวมบัญชีหัวหน้า — /reports/team-calendar นับเฉพาะพนักงานทั่วไป
  /// การใส่หัวหน้าเข้ามาด้วยจะกลายเป็น "ยังไม่ลงเวลา" ค้างอยู่ทุกวัน
  final List<TeamMember> members;

  /// จำนวนบัญชีหัวหน้าในระบบ (ไม่ได้อยู่ใน [members])
  final int managerCount;

  /// เวลาของเซิร์ฟเวอร์ตอนที่ตอบเส้นติดตาม — ใช้บอกว่าข้อมูลสดแค่ไหน
  final DateTime? serverTime;

  const TeamStatus({
    required this.day,
    required this.members,
    required this.managerCount,
    this.serverTime,
  });

  int countOf(DutyState state) =>
      members.where((member) => member.duty == state).length;

  List<TeamMember> whereDuty(DutyState state) =>
      members.where((member) => member.duty == state).toList(growable: false);

  /// คนที่วันนี้ยังไม่ลงเวลา = ยังไม่ได้ยืนยันตัวตน
  List<TeamMember> get absent => whereDuty(DutyState.absent);

  /// คนที่วันนี้ลงเวลาแล้ว (รวมคนที่ลงไว้ที่บ้าน)
  List<TeamMember> get present =>
      members.where((member) => member.checkedIn).toList(growable: false);

  /// กำลังส่งพิกัดอยู่ตอนนี้ (ไม่เกิน 5 นาที ตามที่ backend ตัดสิน)
  int get onlineCount => members
      .where((member) => member.liveStatus == LiveStatus.online)
      .length;

  /// ยังไม่เคยลงทะเบียนใบหน้า — สแกนลงเวลาไม่ได้จนกว่าจะลงทะเบียน
  List<TeamMember> get withoutFace =>
      members.where((member) => !member.faceEnrolled).toList(growable: false);

  static TeamStatus? _cached;
  static DateTime? _cachedAt;
  static Future<TeamStatus>? _inFlight;

  /// อายุของ cache — สั้นพอที่ตัวเลขจะยังสด แต่พอให้แท็บที่เปิดไล่กัน
  /// ไม่ต้องยิงชุดเดียวกันซ้ำ
  static const Duration _cacheFor = Duration(seconds: 30);

  /// ทิ้งข้อมูลที่ค้างไว้ — ต้องเรียกตอนออกจากระบบ
  ///
  /// เครื่องที่ใช้ร่วมกัน คนที่ล็อกอินคนถัดไปต้องไม่เห็นรายชื่อทีมของหัวหน้าคนก่อน
  static void clearCache() {
    _cached = null;
    _cachedAt = null;
  }

  /// โหลดทั้งสามเส้นพร้อมกันแล้วรวมเป็นรายชื่อเดียว (หัวหน้าเท่านั้น)
  ///
  /// [force] = ข้าม cache (ผู้ใช้กดโหลดใหม่เอง หรือเพิ่งแก้ข้อมูลพนักงานมา)
  static Future<TeamStatus> load({bool force = false}) {
    // แท็บภาพรวมกับแท็บข้อมูลพนักงานถูกสร้างพร้อมกันตอนล็อกอิน (IndexedStack)
    // ถ้าปล่อยให้ต่างคนต่างยิง หัวหน้าจะเสีย request สามเส้นฟรี ๆ ทุกครั้ง
    final pending = _inFlight;
    if (pending != null) return pending;

    final cached = _cached;
    final cachedAt = _cachedAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheFor) {
      return Future.value(cached);
    }

    final future = _fetch();
    _inFlight = future;
    return future;
  }

  /// ห่อ [_load] ไว้เพื่อปลดล็อก _inFlight ให้ครบทั้งตอนสำเร็จและตอนพัง
  static Future<TeamStatus> _fetch() async {
    try {
      return await _load();
    } finally {
      _inFlight = null;
    }
  }

  static Future<TeamStatus> _load() async {
    final today = Config.thaiNow();

    // Future.wait รอให้ทุกเส้นจบเสมอ ต่างจากการ await ทีละตัวที่พอเส้นแรกพัง
    // แล้วออกไปก่อน error ของเส้นที่เหลือจะกลายเป็น unhandled exception
    final results = await Future.wait<Object>([
      ApiService.fetchEmployees(),
      ApiService.fetchTeamCalendar(today.year, today.month),
      ApiService.fetchLiveLocations(),
    ]);
    final employees = results[0] as List<EmployeeProfile>;
    final calendar = results[1] as TeamCalendarMonth;
    final live = results[2] as LiveLocationsSnapshot;

    final status = merge(
      today: today,
      employees: employees,
      todayInCalendar: calendar.byDate[thaiDateKey(today)],
      live: live,
    );
    _cached = status;
    _cachedAt = DateTime.now();
    return status;
  }

  /// รวมสามก้อนให้เป็นรายชื่อเดียว — แยกออกจากการยิง API เพื่อให้เทสต์ตรรกะได้
  ///
  /// [todayInCalendar] = ช่องของวันนี้ใน /reports/team-calendar (null ได้ ถ้า
  /// วันนี้ยังไม่มีใครลงเวลาและ backend ไม่ได้ส่งช่องของวันนั้นมา)
  static TeamStatus merge({
    required DateTime today,
    required List<EmployeeProfile> employees,
    required TeamCalendarDay? todayInCalendar,
    required LiveLocationsSnapshot live,
  }) {
    final checkedIn = {
      for (final person in todayInCalendar?.people ?? const <TeamCalendarPerson>[])
        person.employeeId: person,
    };
    final missing = {
      for (final person in todayInCalendar?.missing ?? const <TeamCalendarMissing>[])
        person.employeeId: person,
    };
    final positions = {
      for (final position in live.employees) position.employeeId: position,
    };

    final members = <TeamMember>[];
    for (final profile in employees) {
      if (profile.isManager) continue;
      final person = checkedIn[profile.id];
      members.add(
        TeamMember(
          profile: profile,
          today: person,
          live: positions[profile.id],
          // ปฏิทินส่ง face_enrolled มาทั้งฝั่งคนที่ลงเวลาและฝั่งคนที่ขาด
          // คนที่ไม่โผล่ในทั้งสองฝั่ง (เพิ่งลงทะเบียนกลางเดือน) ถือว่าลงแล้ว
          // ไว้ก่อน ดีกว่าขึ้นป้ายกล่าวหาว่ายังไม่ได้ลงทะเบียนใบหน้า
          faceEnrolled:
              person?.faceEnrolled ?? missing[profile.id]?.faceEnrolled ?? true,
        ),
      );
    }

    members.sort((a, b) {
      final byDuty = a.duty.order.compareTo(b.duty.order);
      return byDuty != 0 ? byDuty : a.fullName.compareTo(b.fullName);
    });

    return TeamStatus(
      day: DateTime(today.year, today.month, today.day),
      members: members,
      managerCount: employees.where((employee) => employee.isManager).length,
      serverTime: live.serverTime,
    );
  }
}
