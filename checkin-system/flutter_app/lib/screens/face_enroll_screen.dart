import 'dart:io';

import 'package:flutter/material.dart';

import '../models/directory.dart';
import '../services/api_service.dart';
import '../widgets/face_scanner.dart';

/// บันทึกรูปใบหน้าอ้างอิงเข้าประวัติของตัวเอง (POST /faces/enroll)
///
/// ต่างจากการลงเวลาตรงที่ "ไม่ผูกกับตำแหน่ง" — เป็นการเก็บรูปอ้างอิงไว้
/// เทียบตัวตนภายหลัง จึงบันทึกได้จากที่ไหนก็ได้ ไม่ต้องอยู่ในเขต
///
/// ก่อนหน้านี้ทำได้เฉพาะบนเว็บ (ต้องเปิดผ่าน HTTPS + อนุญาตกล้องของเบราว์เซอร์)
/// ย้ายมาไว้ในแอปด้วย เพราะพนักงานถือมือถืออยู่แล้วและกล้องหน้าคมกว่า
class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  String _note = '';
  FaceRecord? _saved;

  Future<String?> _submit(File photo) async {
    try {
      final record = await ApiService.enrollFace(photo, note: _note);
      if (mounted) setState(() => _saved = record);
      return null;
    } on ApiException catch (err) {
      return err.message;
    } catch (err) {
      debugPrint('Enroll face failed: $err');
      return 'บันทึกใบหน้าไม่สำเร็จ กรุณาลองใหม่';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_saved != null) return _buildSuccess();

    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกใบหน้าอ้างอิง')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (value) => _note = value,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'บันทึกช่วยจำ (ไม่บังคับ)',
                hintText: 'เช่น ใส่แว่น / ทรงผมใหม่',
                border: OutlineInputBorder(),
                isDense: true,
                counterText: '',
              ),
            ),
          ),
          Expanded(
            child: FaceScanner(
              confirmLabel: 'บันทึกใบหน้านี้',
              footnote: 'รูปนี้ใช้เป็นภาพอ้างอิงเพื่อยืนยันตัวตน '
                  'ไม่ใช่การลงเวลาเข้างาน',
              onCapture: _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกใบหน้าแล้ว')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user, size: 84, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'บันทึกใบหน้าเรียบร้อย',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'รูปนี้ถูกเก็บเข้าประวัติยืนยันตัวตนของคุณแล้ว '
                'หัวหน้าและตัวคุณเองเท่านั้นที่เปิดดูได้',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('เสร็จสิ้น'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
