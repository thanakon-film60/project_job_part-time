import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'checkin_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _pos;
  double? _distanceKm;
  bool _within = false;
  String _status = 'กำลังหาตำแหน่ง...';

  @override
  void initState() {
    super.initState();
    _watch();
  }

  Future<void> _watch() async {
    final ok = await LocationService.ensurePermission();
    if (!ok) {
      setState(() => _status = 'กรุณาเปิด GPS และอนุญาตตำแหน่ง');
      return;
    }
    LocationService.stream().listen((pos) {
      final dist =
          LocationService.distanceFromOfficeKm(pos.latitude, pos.longitude);
      setState(() {
        _pos = pos;
        _distanceKm = dist;
        _within = dist <= Config.geofenceRadiusKm;
        _status = _within
            ? 'อยู่ในเขตออฟฟิศ พร้อมเช็คอิน'
            : 'อยู่นอกเขต (${dist.toStringAsFixed(2)} กม.)';
      });
    });
  }

  Future<void> _goCheckIn(String kind) async {
    if (_pos == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CheckInScreen(
          kind: kind,
          latitude: _pos!.latitude,
          longitude: _pos!.longitude,
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(kind == 'in' ? 'เข้างานสำเร็จ' : 'ออกงานสำเร็จ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _within ? Colors.green : Colors.orange;
    return Scaffold(
      appBar: AppBar(
        title: const Text('เช็คอินเข้างาน'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.logout();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: color.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(_within ? Icons.check_circle : Icons.location_off,
                        size: 56, color: color),
                    const SizedBox(height: 10),
                    Text(_status,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color)),
                    if (_pos != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'พิกัด: ${_pos!.latitude.toStringAsFixed(5)}, '
                        '${_pos!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      Text('ห่างออฟฟิศ ${_distanceKm!.toStringAsFixed(2)} กม.',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _within ? () => _goCheckIn('in') : null,
              icon: const Icon(Icons.login),
              label: const Text('เข้างาน (สแกนหน้า)'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _within ? () => _goCheckIn('out') : null,
              icon: const Icon(Icons.logout),
              label: const Text('ออกงาน (สแกนหน้า)'),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const Spacer(),
            const Text(
              'ต้องอยู่ในรัศมี 2 กม. รอบออฟฟิศ และสแกนใบหน้าผ่าน จึงจะเช็คอินได้',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
