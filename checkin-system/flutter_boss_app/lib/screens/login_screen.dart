import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'app_shell.dart';

class LoginScreen extends StatefulWidget {
  /// ข้อความบอกสาเหตุที่ถูกพากลับมาหน้านี้ (เช่น หมดเวลาใช้งานประจำวัน)
  final String? notice;

  const LoginScreen({super.key, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController(text: 'BOSS001');
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await ApiService.login(_user.text.trim(), _pass.text);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'รหัสพนักงานหรือรหัสผ่านไม่ถูกต้อง';
      });
      return;
    }

    // แอปนี้มีแต่เมนูของหัวหน้า บัญชีพนักงานทั่วไปเข้ามาก็จะเจอจอว่าง
    // ตัดจบตั้งแต่ตรงนี้แล้วบอกให้ไปใช้แอปพนักงานแทน ชัดกว่าปล่อยให้งง
    // (ตัวกันจริงยังเป็น require_manager ที่ backend เหมือนเดิม)
    if (!ApiService.isManager) {
      await ApiService.logout();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'บัญชีนี้ไม่ใช่บัญชีหัวหน้า — '
            'กรุณาใช้แอป THANAKON-BOX เช็คอินเข้างาน สำหรับพนักงาน';
      });
      return;
    }

    setState(() => _loading = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // คีย์บอร์ดเด้งขึ้นแล้วพื้นที่ที่เหลือเตี้ยกว่าฟอร์ม — ถ้าไม่ให้เลื่อนได้
      // ฟอร์มจะล้นจนขึ้นแถบเหลือง-ดำ และปุ่ม "เข้าสู่ระบบ" จะถูกดันหายไป
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            // ยังจัดกลางจอเหมือนเดิมตอนที่พื้นที่พอ (48 = padding บน+ล่าง)
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo-checkin.png',
                    width: 116,
                    height: 116,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  const Text('THANAKON-BOX สำหรับหัวหน้า',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'เข้าได้เฉพาะบัญชีหัวหน้า',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  if (widget.notice != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(child: Text(widget.notice!)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                      labelText: 'รหัสพนักงาน / อีเมล',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่าน',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('เข้าสู่ระบบ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
