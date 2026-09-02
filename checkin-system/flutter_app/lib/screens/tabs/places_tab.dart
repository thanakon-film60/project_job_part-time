import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../config.dart';
import '../../services/api_service.dart';
import '../../services/attendance_service.dart';
import '../../services/location_service.dart';
import '../../services/tracking_controller.dart';
import '../../widgets/tracking_status_card.dart';

/// แท็บ "สถานที่ & สถานะระบบ"
///
/// ตอบคำถามที่พนักงานถามบ่อย: เช็คอินที่ไหนได้บ้าง รัศมีเท่าไร ตอนนี้ห่างแค่ไหน
/// และระบบยังติดตามตำแหน่งอยู่ไหม เหลือเวลาใช้งานอีกเท่าไรก่อนถูกเด้งออก
class PlacesTab extends StatefulWidget {
  final TrackingController tracking;

  const PlacesTab({super.key, required this.tracking});

  @override
  State<PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends State<PlacesTab> {
  Position? _pos;
  bool _loadingOffices = false;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    widget.tracking.addListener(_onTrackingChanged);
    _refresh();
    // เดินนาฬิกา "เหลือเวลาใช้งาน" และความสดของ ping
    _clockTimer = Timer.periodic(Config.workedClockTick, (_) {
      if (mounted) setState(() {});
    });
  }

  void _onTrackingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loadingOffices = true);
    try {
      await LocationService.refreshOfficesFromServer();
    } catch (err) {
      debugPrint('Using bundled geofence settings: $err');
    }
    try {
      if (widget.tracking.access.canTrack) {
        _pos = await LocationService.current().timeout(
          const Duration(seconds: 20),
        );
      }
    } catch (err) {
      debugPrint('Cannot read current position: $err');
    }
    if (!mounted) return;
    setState(() => _loadingOffices = false);
  }

  @override
  void dispose() {
    widget.tracking.removeListener(_onTrackingChanged);
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offices = LocationService.offices;
    final tracking = widget.tracking;
    final trackingLat = tracking.isStale ? null : tracking.lastLatitude;
    final trackingLng = tracking.isStale ? null : tracking.lastLongitude;
    final fromLat = _pos?.latitude ?? trackingLat;
    final fromLng = _pos?.longitude ?? trackingLng;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TrackingStatusCard(
            access: tracking.access,
            serviceRunning: tracking.running,
            preparing: tracking.preparing,
            lastPingAt: tracking.lastPingAt,
            onGrant: () => tracking.ensure(prompt: true),
            onOpenSettings: LocationService.openSettings,
            onOpenGps: LocationService.openLocationSettings,
          ),
          const SizedBox(height: 12),
          const _SessionCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'สถานที่ที่เช็คอินได้',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              if (_loadingOffices)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'โหลดใหม่จากเซิร์ฟเวอร์',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...offices.map(
            (office) => _OfficeCard(
              office: office,
              fromLat: fromLat,
              fromLng: fromLng,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'รายการนี้ดึงจากเซิร์ฟเวอร์ (/reports/geofence) ทุกครั้งที่เปิดแท็บ '
            'จึงตรงกับเงื่อนไขที่ระบบใช้ตัดสินจริงตอนกดยืนยัน',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// เหลือเวลาใช้งานอีกเท่าไรก่อนถูกเด้งออกตอน 4 ทุ่ม
class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final endsAt = ApiService.sessionEndsAt;
    final left = ApiService.timeLeftInSession;
    final soon = left != null && left < const Duration(hours: 1);

    return Card(
      color: (soon ? Colors.orange : Colors.indigo).withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.timer_outlined,
                color: soon ? Colors.orange : Colors.indigo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เวลาใช้งานประจำวัน',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    endsAt == null
                        ? 'ยังไม่ได้เข้าสู่ระบบ'
                        : 'ระบบจะให้ออกจากระบบตอน ${thaiClock(endsAt)} น. '
                            '(เหลืออีก ${humanDuration(left ?? Duration.zero)})',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfficeCard extends StatelessWidget {
  final Office office;
  final double? fromLat;
  final double? fromLng;

  const _OfficeCard({
    required this.office,
    required this.fromLat,
    required this.fromLng,
  });

  @override
  Widget build(BuildContext context) {
    double? distanceKm;
    if (fromLat != null && fromLng != null) {
      distanceKm = LocationService.distanceBetweenKm(
        fromLat!,
        fromLng!,
        office.lat,
        office.lng,
      );
    }
    final inside = distanceKm != null && distanceKm <= office.radiusKm;
    final color = inside ? Colors.green : Colors.blueGrey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(inside ? Icons.my_location : Icons.place_outlined,
                    color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    office.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (!office.allowCheckout)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ออกงานไม่ได้',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'รัศมีที่อนุญาต ${office.radiusKm.toStringAsFixed(2)} กม. · '
              'พิกัด ${office.lat.toStringAsFixed(5)}, '
              '${office.lng.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 2),
            Text(
              distanceKm == null
                  ? 'ยังอ่านตำแหน่งปัจจุบันไม่ได้'
                  : inside
                      ? 'ตอนนี้อยู่ในเขต (ห่าง ${_distanceText(distanceKm)})'
                      : 'ตอนนี้ห่าง ${_distanceText(distanceKm)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _distanceText(double km) => km < 1
      ? '${(km * 1000).toStringAsFixed(0)} ม.'
      : '${km.toStringAsFixed(2)} กม.';
}
