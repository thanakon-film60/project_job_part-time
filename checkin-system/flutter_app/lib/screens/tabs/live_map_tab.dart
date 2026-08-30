import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/live_location.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../services/location_service.dart';
import '../../widgets/app_forms.dart';

/// รีเฟรชอัตโนมัติทุกกี่วินาที — เท่ากับฝั่งเว็บ
const Duration _refreshInterval = Duration(seconds: 20);

/// จุดกึ่งกลางเริ่มต้นเมื่อยังไม่มีข้อมูลอะไรเลย (บางบัวทอง)
const LatLng _defaultCenter = LatLng(13.8712, 100.4155);

/// ซูมได้ลึกสุดเท่าที่ tile ของ OpenStreetMap มีจริง (สูงสุดคือ 19)
/// เผื่อไว้หนึ่งระดับ ภาพจะได้ยังคมอยู่
const double _maxZoom = 18;

/// เพดานตอนซูมให้เห็นทุกคนพร้อมกัน — เห็นบริบทรอบตัวด้วย ไม่ใช่จ่อจนติดหลังคา
const double _fitMaxZoom = 17;

/// แท็บ "แผนที่ติดตาม" (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/pages/LiveMapPage.jsx — ตำแหน่งล่าสุดของทุกคน
/// วงเขตที่เช็คอินได้ และเส้นทางย้อนหลังของคนที่เลือก
class LiveMapTab extends StatefulWidget {
  const LiveMapTab({super.key});

  @override
  State<LiveMapTab> createState() => _LiveMapTabState();
}

class _LiveMapTabState extends State<LiveMapTab> {
  final MapController _map = MapController();

  LiveLocationsSnapshot? _data;
  bool _loading = false;
  String? _error;
  Timer? _timer;

  /// กันรอบรีเฟรชใหม่ซ้อนกับ request ที่ยังไม่จบ
  bool _inFlight = false;

  /// เผื่อ fitCamera ครั้งแรกหลังได้ข้อมูล — หลังจากนั้นปล่อยให้ผู้ใช้คุมเอง
  bool _fitted = false;

  int? _selectedId;
  int _trailHours = 0; // 0 = ไม่แสดงเส้นทาง
  List<TrailPoint> _trail = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load(silent: true));
    // วงเขตบนแผนที่ต้องตรงกับ OFFICES ล่าสุดของ backend
    LocationService.refreshOfficesFromServer().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object err) {
      debugPrint('Using bundled geofence settings on map: $err');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_inFlight || !ApiService.isLoggedIn) return;
    _inFlight = true;
    if (!silent && mounted) setState(() => _loading = true);

    try {
      final data = await ApiService.fetchLiveLocations();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      _fitAllOnce(data);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Load live locations failed: $err');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'โหลดตำแหน่งพนักงานไม่สำเร็จ';
      });
    } finally {
      _inFlight = false;
    }
  }

  /// ครอบคลุมทุกหมุดในครั้งแรกที่โหลดได้ หัวหน้าจะได้ไม่ต้องซูมหาเอง
  void _fitAllOnce(LiveLocationsSnapshot data) {
    if (_fitted) return;
    final points = data.located
        .map((employee) => LatLng(employee.latitude!, employee.longitude!))
        .toList(growable: false);
    if (points.isEmpty) return;
    _fitted = true;

    if (points.length == 1) {
      _map.move(points.first, 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(40),
        // ทุกคนยืนอยู่จุดเดียวกัน = กรอบเล็กจิ๋ว ถ้าไม่คุมไว้จะซูมทะลุ
        // จนไม่เหลือแผนที่ให้ดู
        maxZoom: _fitMaxZoom,
      ),
    );
  }

  Future<void> _select(LiveLocation employee) async {
    setState(() => _selectedId = employee.employeeId);
    if (employee.hasPosition) {
      _map.move(
        LatLng(employee.latitude!, employee.longitude!),
        _map.camera.zoom < 16 ? 16 : _map.camera.zoom,
      );
    }
    await _loadTrail();
  }

  Future<void> _loadTrail() async {
    final employeeId = _selectedId;
    if (employeeId == null || _trailHours == 0) {
      if (mounted) setState(() => _trail = const []);
      return;
    }
    try {
      final trail = await ApiService.fetchLocationTrail(
        employeeId,
        hours: _trailHours,
      );
      if (!mounted) return;
      setState(() => _trail = trail);
    } catch (err) {
      debugPrint('Load trail failed: $err');
      if (!mounted) return;
      setState(() => _trail = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final counts = data?.counts ?? const <LiveStatus, int>{};

    return Column(
      children: [
        _statusBar(counts),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.4,
          child: Stack(
            children: [
              _buildMap(data),
              if (_loading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  heroTag: 'live-map-refresh',
                  tooltip: 'โหลดใหม่',
                  onPressed: () => _load(),
                  child: const Icon(Icons.refresh),
                ),
              ),
            ],
          ),
        ),
        if (_selectedId != null) _trailControls(),
        Expanded(
          child: _error != null
              ? NoticeBox.error(text: _error!, onRetry: () => _load())
              : data == null
                  ? const NoticeBox.loading(
                      text: 'กำลังโหลดตำแหน่งพนักงาน...',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: data.employees.length,
                        itemBuilder: (context, index) {
                          final employee = data.employees[index];
                          return _EmployeeRow(
                            employee: employee,
                            selected: employee.employeeId == _selectedId,
                            onTap: () => _select(employee),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _statusBar(Map<LiveStatus, int> counts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final status in LiveStatus.values)
            Tag(
              text: '${status.label} ${counts[status] ?? 0}',
              color: liveStatusColor(status),
              icon: Icons.circle,
            ),
        ],
      ),
    );
  }

  Widget _buildMap(LiveLocationsSnapshot? data) {
    final located = data?.located ?? const <LiveLocation>[];

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 13,
        // OSM มี tile ถึง zoom 19 เท่านั้น เกินกว่านี้แผนที่จะกลายเป็นพื้นเทา
        // เพราะเหลือ tile เดียวถูกขยายจนเบลอ — กันไว้ทั้งการซูมด้วยนิ้วและ
        // การ fitCamera (ดู _fitAllOnce: คนสองคนที่อยู่ห่างกันไม่กี่เมตร
        // ทำให้กรอบเล็กจนคำนวณซูมได้ถึง 24)
        maxZoom: _maxZoom,
        // แตะที่ว่างบนแผนที่ = เลิกเลือกคน (เส้นทางหายไปด้วย)
        onTap: (_, __) => setState(() {
          _selectedId = null;
          _trail = const [];
        }),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // OSM บังคับให้ระบุตัวตนของแอปที่เรียกใช้ ตาม usage policy ของเขา
          userAgentPackageName: 'com.mardodi.mardodi_checkin',
          // แผนที่ว่างเปล่าเป็นอาการที่ debug ยากมาก เพราะ flutter_map กลืน
          // error ของ tile ไว้เงียบๆ — log ไว้จะได้รู้ว่าติดที่เน็ต ที่ 403
          // หรือที่การถอดรหัสรูป (debugPrint ถูกตัดทิ้งใน release อยู่แล้ว)
          errorTileCallback: (tile, error, stackTrace) =>
              debugPrint('TILE FAIL ${tile.coordinates}: $error'),
        ),
        CircleLayer(
          circles: [
            for (final office in LocationService.offices)
              CircleMarker(
                point: LatLng(office.lat, office.lng),
                // รัศมีใน config เป็นกิโลเมตร ส่วน flutter_map ใช้เมตร
                radius: office.radiusKm * 1000,
                useRadiusInMeter: true,
                color: (office.isHome ? Colors.deepPurple : Colors.blue)
                    .withValues(alpha: 0.10),
                borderColor: office.isHome ? Colors.deepPurple : Colors.blue,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        if (_trail.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  for (final point in _trail)
                    LatLng(point.latitude, point.longitude),
                ],
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 3,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final employee in located)
              Marker(
                point: LatLng(employee.latitude!, employee.longitude!),
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => _select(employee),
                  child: _MapPin(
                    employee: employee,
                    selected: employee.employeeId == _selectedId,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _trailControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Text('เส้นทางย้อนหลัง', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 0, label: Text('ปิด')),
                ButtonSegment(value: 6, label: Text('6 ชม.')),
                ButtonSegment(value: 24, label: Text('24 ชม.')),
              ],
              selected: {_trailHours},
              onSelectionChanged: (selection) {
                setState(() => _trailHours = selection.first);
                _loadTrail();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// หมุดพนักงานบนแผนที่ — วงกลมสีตามสถานะ + อักษรย่อของชื่อ
class _MapPin extends StatelessWidget {
  final LiveLocation employee;
  final bool selected;

  const _MapPin({required this.employee, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = liveStatusColor(employee.status);
    final initial =
        employee.fullName.isEmpty ? '?' : employee.fullName.substring(0, 1);

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.black87 : Colors.white,
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4),
        ],
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// พนักงาน 1 คนในรายชื่อใต้แผนที่
class _EmployeeRow extends StatelessWidget {
  final LiveLocation employee;
  final bool selected;
  final VoidCallback onTap;

  const _EmployeeRow({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = liveStatusColor(employee.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        onTap: employee.hasPosition ? onTap : null,
        leading: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(
          employee.fullName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employee.whereShortText,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '${employee.status.label} · ${employee.ageText}'
              '${employee.timestamp == null ? '' : ' (${thaiClock(employee.timestamp!)} น.)'}',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
        trailing: employee.hasPosition
            ? const Icon(Icons.my_location, size: 18)
            : null,
      ),
    );
  }
}
