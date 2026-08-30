import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';

/// หน้ายืนยันการลงเวลาของหัวหน้า — ไม่มีการสแกนใบหน้า
///
/// ต่างจากแอปพนักงานตรงนี้จุดเดียว: พนักงานต้องสแกนหน้าผ่าน liveness ก่อน
/// ทุกครั้ง ส่วนหัวหน้ากดยืนยันได้เลย (backend ยกเว้นให้เฉพาะบัญชี is_manager
/// — ดู `face_detected` ใน backend/app/routers/checkins.py)
///
/// สิ่งที่ยังเหมือนเดิมคือ **ต้องอยู่ในเขตที่กำหนด** และระบบอ่าน GPS ใหม่
/// ตอนกดยืนยันเสมอ ไม่ใช้พิกัดที่อ่านค้างไว้ตอนเปิดหน้า
class CheckInScreen extends StatefulWidget {
  final String kind; // "in" หรือ "out"

  const CheckInScreen({super.key, required this.kind});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  CheckInResult? _savedResult;
  bool _saving = false;
  String? _error;

  bool get _isCheckOut => widget.kind == 'out';

  String get _action => _isCheckOut ? 'ออกงาน' : 'เข้างาน';

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final double latitude;
    final double longitude;
    try {
      try {
        await LocationService.refreshOfficesFromServer();
      } catch (err) {
        debugPrint('Using bundled geofence settings before submit: $err');
      }

      final position =
          await LocationService.current().timeout(const Duration(seconds: 20));
      final (office, distanceKm, within) = LocationService.nearestOffice(
        position.latitude,
        position.longitude,
        workOnly: _isCheckOut,
      );
      if (!within) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = '$_actionไม่ได้: อยู่นอกเขต ${office.name} '
              '(ห่าง ${distanceKm.toStringAsFixed(2)} กม. / '
              'กำหนด ${office.radiusKm.toStringAsFixed(2)} กม.)';
        });
        return;
      }
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (err) {
      debugPrint('Read position before submit failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'ตรวจสอบ GPS ไม่ได้ กรุณาเปิดตำแหน่งแล้วลองใหม่';
      });
      return;
    }

    final result = await ApiService.checkIn(
      lat: latitude,
      lng: longitude,
      kind: widget.kind,
      // ไม่มีการสแกนใบหน้าในแอปนี้ — ส่งตามจริง แล้วให้ backend ตัดสินว่า
      // บัญชีนี้ได้รับการยกเว้นหรือไม่ ไม่ใช่ให้แอปโกหกว่าสแกนแล้ว
      faceDetected: false,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _saving = false;
        _error = result.message;
      });
      return;
    }
    setState(() {
      _saving = false;
      _savedResult = result;
    });
  }

  String _formatDistance(double? distanceKm) {
    if (distanceKm == null) return '-';
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} เมตร';
    return '${distanceKm.toStringAsFixed(2)} กม.';
  }

  Widget _buildSuccess(CheckInResult result) {
    final action = result.kind == 'out' ? 'ออกงาน' : 'เข้างาน';
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกเสร็จแล้ว')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 84, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'บันทึกเสร็จแล้ว',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('ระบบบันทึกการ$actionของคุณแล้ว'),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('ช่วงเวลา'),
                      subtitle: Text(thaiDateTime(result.timestamp)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.place),
                      title: const Text('จุดทำงาน'),
                      subtitle: Text(result.officeName ?? '-'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.social_distance),
                      title: const Text('ระยะทาง'),
                      subtitle: Text(_formatDistance(result.distanceKm)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('กลับหน้าแรก'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savedResult = _savedResult;
    if (savedResult != null) return _buildSuccess(savedResult);

    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text('ยืนยัน$_action')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isCheckOut ? Icons.logout : Icons.login,
                size: 84,
                color: _isCheckOut ? Colors.deepOrange : Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                'ยืนยัน$_action',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'บัญชีหัวหน้าลงเวลาได้โดยไม่ต้องสแกนใบหน้า '
                'ระบบจะตรวจ GPS อีกครั้งตอนกดยืนยัน',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'กำลังบันทึก...' : 'ยืนยัน$_action'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
