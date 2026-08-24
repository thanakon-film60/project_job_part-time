import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  /// ข้อความบอกสาเหตุที่ถูกพากลับมาหน้านี้ (เช่น หมดเวลาใช้งานประจำวัน)
  final String? notice;

  const LoginScreen({super.key, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController(text: 'EMP001');
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
    setState(() => _loading = false);
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() => _error = 'รหัสพนักงานหรือรหัสผ่านไม่ถูกต้อง');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const Text('THANAKON-BOX เช็คอินเข้างาน',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                      ? const CircularProgressIndicator()
                      : const Text('เข้าสู่ระบบ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
