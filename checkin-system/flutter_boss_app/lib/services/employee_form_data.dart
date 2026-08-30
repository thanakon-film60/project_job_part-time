import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/directory.dart';
import 'api_service.dart';
import 'employee_registration.dart';

/// ข้อมูลอ้างอิงที่ฟอร์มพนักงานต้องใช้: แผนก/ตำแหน่ง และที่อยู่ตามรหัสไปรษณีย์
///
/// ทั้งฟอร์มลงทะเบียนใหม่และฟอร์มแก้ไขต้องการชุดเดียวกันเป๊ะ จึงยกมาไว้ที่นี่
/// แทนที่จะให้แต่ละหน้าจัดการ debounce/สถานะการค้นเองแล้วเพี้ยนคนละแบบ
class EmployeeFormData extends ChangeNotifier {
  List<EmploymentOption> _options = const [];
  String? optionsError;
  bool optionsLoading = false;

  List<ThaiAddress> _addresses = const [];
  AddressLookup _lookup = AddressLookup.idle;
  Timer? _debounce;

  /// รหัสไปรษณีย์ของผลค้นชุดที่ถืออยู่ตอนนี้ — กันผลของ request เก่า
  /// ที่กลับมาช้ากว่ามาทับผลของรหัสที่ผู้ใช้พิมพ์ล่าสุด
  String _pendingPostalCode = '';

  List<EmploymentOption> get departments =>
      _options.where((option) => option.isDepartment).toList(growable: false);

  List<EmploymentOption> get positions =>
      _options.where((option) => option.isPosition).toList(growable: false);

  List<ThaiAddress> get addresses => _addresses;
  AddressLookup get lookup => _lookup;

  Future<void> loadOptions() async {
    optionsLoading = true;
    optionsError = null;
    notifyListeners();
    try {
      _options = await ApiService.fetchEmploymentOptions();
    } on ApiException catch (err) {
      optionsError = err.message;
    } catch (err) {
      debugPrint('Load employment options failed: $err');
      optionsError = 'โหลดแผนกและตำแหน่งไม่สำเร็จ';
    } finally {
      optionsLoading = false;
      notifyListeners();
    }
  }

  /// เพิ่มแผนก/ตำแหน่งใหม่แล้วให้อยู่ในรายการทันที
  Future<EmploymentOption> addOption(String kind, String name) async {
    final created = await ApiService.addEmploymentOption(kind, name);
    _options = [..._options, created];
    notifyListeners();
    return created;
  }

  /// ค้นที่อยู่จากรหัสไปรษณีย์ — หน่วงไว้ก่อนยิงจริง เพราะผู้ใช้พิมพ์ทีละหลัก
  void searchPostalCode(String postalCode) {
    _debounce?.cancel();
    _pendingPostalCode = postalCode;

    if (!RegExp(r'^\d{5}$').hasMatch(postalCode)) {
      _addresses = const [];
      _lookup = AddressLookup.idle;
      notifyListeners();
      return;
    }

    _addresses = const [];
    _lookup = AddressLookup.loading;
    notifyListeners();

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final rows = await ApiService.fetchThaiAddresses(postalCode);
        if (_pendingPostalCode != postalCode) return; // ผู้ใช้พิมพ์ต่อไปแล้ว
        _addresses = rows;
        _lookup = AddressLookup.success;
      } catch (err) {
        debugPrint('Postal code lookup failed: $err');
        if (_pendingPostalCode != postalCode) return;
        _addresses = const [];
        _lookup = AddressLookup.error;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
