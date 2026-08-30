import 'package:flutter/material.dart';

import '../models/directory.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/employee_form_data.dart';
import '../services/employee_registration.dart';
import '../widgets/app_forms.dart';

/// แก้ไขแฟ้มพนักงาน (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/components/EmployeeEditDialog.jsx — บนมือถือใช้
/// เป็นหน้าเต็มแทน dialog เพราะฟอร์มมี 13 ช่องกับคีย์บอร์ดที่กินพื้นที่ครึ่งจอ
///
/// ส่งเฉพาะช่องที่เปลี่ยนจริงตาม PATCH ที่ backend รองรับ (exclude_unset)
/// ไม่งั้น Timeline แฟ้มพนักงานจะมีรายการ "แก้ไขข้อมูล" ทั้งที่ไม่ได้แก้อะไร
class EmployeeEditScreen extends StatefulWidget {
  final EmployeeProfile employee;

  const EmployeeEditScreen({super.key, required this.employee});

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  late final ProfileEditDraft _draft = ProfileEditDraft.from(widget.employee);
  final EmployeeFormData _formData = EmployeeFormData();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _formData.addListener(_onFormDataChanged);
    _formData.loadOptions();
    // มีรหัสไปรษณีย์เดิมอยู่แล้ว ค้นทันทีเพื่อให้ตัวเลือกตำบลพร้อมใช้
    if (_draft.postalCode.isNotEmpty) {
      _formData.searchPostalCode(_draft.postalCode);
    }
  }

  void _onFormDataChanged() {
    if (!mounted) return;
    // ผลค้นที่อยู่กลับมาแล้ว — จับคู่กับที่อยู่เดิมของพนักงานให้ dropdown
    // แสดงค่าที่เลือกไว้ ไม่ใช่ว่างเปล่าทั้งที่ข้อมูลมีอยู่
    _draft.address ??= _formData.addresses
        .where((row) => row.matches(
              _draft.subdistrict,
              _draft.district,
              _draft.province,
            ))
        .firstOrNull;
    setState(() {});
  }

  @override
  void dispose() {
    _formData.removeListener(_onFormDataChanged);
    _formData.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = _draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final changes = _draft.changedFields();
    if (changes.isEmpty) {
      setState(() => _error = 'ยังไม่มีข้อมูลที่แก้ไข');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.updateEmployeeProfile(widget.employee.id, changes);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Update employee failed: $err');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'แก้ไขข้อมูลไม่สำเร็จ กรุณาลองใหม่';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text('แก้ไข ${widget.employee.employeeCode}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'การแก้ไขจะถูกบันทึกลง Timeline แฟ้มพนักงาน '
            'เลขบัตรประชาชนเดิมจะไม่ถูกเปิดเผย',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'ชื่อ-นามสกุล',
            value: _draft.fullName,
            onChanged: (value) => _draft.fullName = value,
          ),
          AppDateField(
            label: 'วันเกิด',
            value: _draft.birthDate,
            lastDate: now,
            onChanged: (value) => setState(() => _draft.birthDate = value),
          ),
          AppTextField(
            label: _draft.nationalIdRequired
                ? 'เลขบัตรประชาชน'
                : 'เลขบัตรประชาชนใหม่ (ไม่บังคับ)',
            hint: _draft.nationalIdRequired
                ? 'กรอกเลขบัตร 13 หลัก'
                : 'เว้นว่างเพื่อใช้เลขเดิม (${widget.employee.nationalIdMasked})',
            value: _draft.nationalId,
            digitsOnly: true,
            maxLength: 13,
            onChanged: (value) => _draft.nationalId = value,
          ),
          AppTextField(
            label: 'เบอร์โทร',
            value: _draft.phone,
            digitsOnly: true,
            maxLength: 10,
            keyboardType: TextInputType.phone,
            onChanged: (value) => _draft.phone = value,
          ),
          AppTextField(
            label: 'อีเมล',
            value: _draft.email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (value) => _draft.email = value,
          ),
          AppTextField(
            label: 'บ้านเลขที่ / ถนน / ซอย',
            value: _draft.addressLine,
            onChanged: (value) => _draft.addressLine = value,
          ),
          AppTextField(
            label: 'รหัสไปรษณีย์',
            value: _draft.postalCode,
            digitsOnly: true,
            maxLength: 5,
            onChanged: (value) {
              setState(() => _draft.setPostalCode(value));
              _formData.searchPostalCode(value);
            },
          ),
          _addressPicker(),
          AppDropdownField<String>(
            label: 'แผนก',
            value: _draft.department.isEmpty ? null : _draft.department,
            hint: 'เลือกแผนก',
            items: [
              for (final option in _formData.departments)
                DropdownMenuItem(value: option.name, child: Text(option.name)),
            ],
            onChanged: (value) =>
                setState(() => _draft.department = value ?? ''),
          ),
          AppDropdownField<String>(
            label: 'ตำแหน่ง',
            value: _draft.position.isEmpty ? null : _draft.position,
            hint: 'เลือกตำแหน่ง',
            items: [
              for (final option in _formData.positions)
                DropdownMenuItem(value: option.name, child: Text(option.name)),
            ],
            onChanged: (value) => setState(() => _draft.position = value ?? ''),
          ),
          AppDateField(
            label: 'วันเริ่มงาน',
            value: _draft.startDate,
            onChanged: (value) => setState(() => _draft.startDate = value),
          ),
          if (_formData.optionsError != null)
            NoticeBox.error(
              text: _formData.optionsError!,
              onRetry: _formData.loadOptions,
            ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: 18, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('บันทึกการแก้ไข'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _addressPicker() {
    return AddressPicker(
      addresses: _formData.addresses,
      lookup: _formData.lookup,
      selected: _draft.address,
      onSelected: (value) => setState(() => _draft.selectAddress(value)),
      subdistrict: _draft.subdistrict,
      district: _draft.district,
      province: _draft.province,
    );
  }
}

/// ตัวเลือกตำบล/อำเภอ/จังหวัด จากผลค้นรหัสไปรษณีย์ + สรุปที่เลือกไว้
///
/// ใช้ทั้งฟอร์มแก้ไขและฟอร์มลงทะเบียน — backend ตรวจว่าที่อยู่ต้องตรงกับ
/// ฐานข้อมูลรหัสไปรษณีย์ จึงให้เลือกจากรายการเท่านั้น พิมพ์เองไม่ได้
class AddressPicker extends StatelessWidget {
  final List<ThaiAddress> addresses;
  final AddressLookup lookup;
  final ThaiAddress? selected;
  final ValueChanged<ThaiAddress> onSelected;
  final String subdistrict;
  final String district;
  final String province;
  final String? error;

  const AddressPicker({
    super.key,
    required this.addresses,
    required this.lookup,
    required this.selected,
    required this.onSelected,
    required this.subdistrict,
    required this.district,
    required this.province,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final hint = switch (lookup) {
      AddressLookup.loading => 'กำลังค้นหา...',
      AddressLookup.error => 'ค้นหาที่อยู่ไม่สำเร็จ',
      AddressLookup.idle => 'กรอกรหัสไปรษณีย์ 5 หลักก่อน',
      AddressLookup.success =>
        addresses.isEmpty ? 'ไม่พบรหัสไปรษณีย์นี้' : 'เลือกที่อยู่',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<int>(
          label: 'เลือกตำบล / อำเภอ / จังหวัด',
          value: selected?.id,
          hint: hint,
          error: error,
          enabled: addresses.isNotEmpty,
          items: [
            for (final row in addresses)
              DropdownMenuItem(value: row.id, child: Text(row.label)),
          ],
          onChanged: (id) {
            final row = addresses.where((item) => item.id == id).firstOrNull;
            if (row != null) onSelected(row);
          },
        ),
        if (subdistrict.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'ต.$subdistrict / อ.$district / จ.$province',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}
