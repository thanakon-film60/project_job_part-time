import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';
import '../widgets/face_scanner.dart';

/// หน้าจอสแกนใบหน้า: เปิดกล้องหน้า ตรวจ liveness แล้วถ่ายรูปส่งเช็คอิน
///
/// เรื่องกล้อง/liveness อยู่ใน FaceScanner ทั้งหมด หน้านี้เหลือแค่
/// ตรรกะของการลงเวลา: ตรวจ GPS ใหม่ก่อนบันทึก แล้วโชว์สรุปเมื่อสำเร็จ
class CheckInScreen extends StatefulWidget {
  final String kind; // "in" หรือ "out"

  const CheckInScreen({super.key, required this.kind});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  CheckInResult? _savedResult;

  bool get _isCheckOut => widget.kind == 'out';

  /// ตรวจ GPS อีกครั้งแล้วส่งเข้าระบบ
  ///
  /// ห้ามใช้พิกัดที่อ่านไว้ตอนเปิดหน้า เพราะผู้ใช้อาจเดินออกนอกเขต
  /// ระหว่างสแกนใบหน้า — ต้องอ่านใหม่ทุกครั้งก่อนบันทึกจริง
  Future<String?> _submit(File photo) async {
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
        final action = _isCheckOut ? 'ออกงานไม่ได้' : 'เข้างานไม่ได้';
        return '$action: อยู่นอกเขต ${office.name} '
            '(ห่าง ${distanceKm.toStringAsFixed(2)} กม. / '
            'กำหนด ${office.radiusKm.toStringAsFixed(2)} กม.)';
      }
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (err) {
      debugPrint('Read position before submit failed: $err');
      return 'ตรวจสอบ GPS ไม่ได้ กรุณาเปิดตำแหน่งแล้วลองใหม่';
    }

    final result = await ApiService.checkIn(
      lat: latitude,
      lng: longitude,
      kind: widget.kind,
      faceDetected: true,
      photo: photo,
    );
    if (!result.success) return result.message;

    if (mounted) setState(() => _savedResult = result);
    return null;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCheckOut ? 'สแกนหน้า - ออกงาน' : 'สแกนหน้า - เข้างาน'),
      ),
      body: FaceScanner(
        confirmLabel: _isCheckOut ? 'ยืนยันออกงาน' : 'ยืนยันเข้างาน',
        footnote: 'ระบบจะตรวจ GPS อีกครั้งตอนกดยืนยัน',
        onCapture: _submit,
      ),
    );
  }
}
