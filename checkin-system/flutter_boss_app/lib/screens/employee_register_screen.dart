import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/employee_form_data.dart';
import '../services/employee_registration.dart';
import '../widgets/app_forms.dart';
import 'employee_edit_screen.dart' show AddressPicker;

/// ลงทะเบียนพนักงานใหม่ (หัวหน้าเท่านั้น)
///
/// พอร์ตจาก frontend/src/pages/EmployeeRegistrationPage.jsx พร้อมกฎตรวจ
/// ชุดเดียวกัน (services/employee_registration.dart) — แบ่ง 3 ขั้นเหมือนเว็บ
/// เพราะ 13 ช่องรวดเดียวบนมือถืออ่านไม่ไหว และผู้ใช้จะไม่รู้ว่าพลาดตรงไหน
class EmployeeRegisterScreen extends StatefulWidget {
  const EmployeeRegisterScreen({super.key});

  @override
  State<EmployeeRegisterScreen> createState() => _EmployeeRegisterScreenState();
}

class _EmployeeRegisterScreenState extends State<EmployeeRegisterScreen> {
  static const List<String> _stepTitles = [
    'ข้อมูลส่วนตัว',
    'การติดต่อและที่อยู่',
    'ข้อมูลการทำงาน',
  ];

  final RegistrationDraft _draft = RegistrationDraft();
  final EmployeeFormData _formData = EmployeeFormData();

  int _step = 0;

  /// ช่องที่ผู้ใช้แตะแล้ว — ยังไม่แตะก็ยังไม่ต้องขึ้นสีแดงใส่หน้าเขา
  final Set<String> _touched = {};

  bool _submitting = false;
  String? _error;
  EmployeeRegistrationResult? _result;

  @override
  void initState() {
    super.initState();
    _formData.addListener(_onFormDataChanged);
    _formData.loadOptions();
  }

  void _onFormDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _formData.removeListener(_onFormDataChanged);
    _formData.dispose();
    super.dispose();
  }

  Map<String, String> get _errors => validateRegistration(
        _draft,
        addressOptions: _formData.addresses,
        lookup: _formData.lookup,
      );

  /// ข้อความผิดพลาดของช่องนี้ — โชว์เฉพาะช่องที่ผู้ใช้แตะไปแล้ว
  String? _errorFor(String field) =>
      _touched.contains(field) ? _errors[field] : null;

  void _update(String field, VoidCallback change) {
    setState(() {
      change();
      _touched.add(field);
    });
  }

  void _next() {
    final errors = _errors;
    if (!registrationStepValid(_step, errors)) {
      // แตะทุกช่องของขั้นนี้ให้อัตโนมัติ ผู้ใช้จะได้เห็นว่าค้างตรงไหน
      setState(() => _touched.addAll(registrationStepFields[_step]));
      return;
    }
    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ApiService.registerEmployee(_draft.toPayload());
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _result = result;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.message;
      });
    } catch (err) {
      debugPrint('Register employee failed: $err');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'ลงทะเบียนพนักงานไม่สำเร็จ กรุณาลองใหม่';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _buildSuccess(result);

    final isLastStep = _step == _stepTitles.length - 1;

    return Scaffold(
      appBar: AppBar(title: const Text('ลงทะเบียนพนักงาน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stepIndicator(),
          const SizedBox(height: 16),
          Text(
            _stepTitles[_step],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._stepFields(),
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
          Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _submitting ? null : () => setState(() => _step--),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('ย้อนกลับ'),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _next,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isLastStep ? Icons.person_add : Icons.arrow_forward,
                          size: 18,
                        ),
                  label: Text(isLastStep ? 'ลงทะเบียน' : 'ถัดไป'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepIndicator() {
    return Row(
      children: [
        for (var index = 0; index < _stepTitles.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 2,
                color: index <= _step
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
            ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index <= _step
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: index <= _step
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
            ),
            child: index < _step
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: index <= _step ? Colors.white : Colors.black45,
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  List<Widget> _stepFields() {
    switch (_step) {
      case 0:
        return _personalFields();
      case 1:
        return _contactFields();
      default:
        return _employmentFields();
    }
  }

  List<Widget> _personalFields() {
    final now = DateTime.now();
    return [
      AppTextField(
        key: const ValueKey('firstName'),
        label: 'ชื่อ',
        value: _draft.firstName,
        error: _errorFor('firstName'),
        onChanged: (value) => _update('firstName', () => _draft.firstName = value),
      ),
      AppTextField(
        key: const ValueKey('lastName'),
        label: 'นามสกุล',
        value: _draft.lastName,
        error: _errorFor('lastName'),
        onChanged: (value) => _update('lastName', () => _draft.lastName = value),
      ),
      AppDateField(
        label: 'วันเกิด',
        value: _draft.birthDate,
        lastDate: now,
        error: _errorFor('birthDate'),
        onChanged: (value) => _update('birthDate', () => _draft.birthDate = value),
      ),
      AppTextField(
        key: const ValueKey('nationalId'),
        label: 'เลขบัตรประชาชน',
        hint: 'ตัวเลข 13 หลัก',
        value: _draft.nationalId,
        digitsOnly: true,
        maxLength: 13,
        // เลขบัตรต้องแจ้งผลทันทีตั้งแต่เริ่มกรอก (เหมือนฝั่งเว็บ)
        error: _errors['nationalId'] != null && _draft.nationalId.isNotEmpty
            ? _errors['nationalId']
            : _errorFor('nationalId'),
        onChanged: (value) =>
            _update('nationalId', () => _draft.nationalId = value),
      ),
    ];
  }

  List<Widget> _contactFields() {
    return [
      AppTextField(
        key: const ValueKey('phone'),
        label: 'เบอร์โทร',
        hint: 'เช่น 0812345678',
        value: _draft.phone,
        digitsOnly: true,
        maxLength: 10,
        keyboardType: TextInputType.phone,
        error: _errorFor('phone'),
        onChanged: (value) => _update('phone', () => _draft.phone = value),
      ),
      AppTextField(
        key: const ValueKey('email'),
        label: 'อีเมล',
        value: _draft.email,
        keyboardType: TextInputType.emailAddress,
        error: _errorFor('email'),
        onChanged: (value) => _update('email', () => _draft.email = value),
      ),
      AppTextField(
        key: const ValueKey('addressLine'),
        label: 'บ้านเลขที่ / ถนน / ซอย',
        value: _draft.addressLine,
        error: _errorFor('addressLine'),
        onChanged: (value) =>
            _update('addressLine', () => _draft.addressLine = value),
      ),
      AppTextField(
        key: const ValueKey('postalCode'),
        label: 'รหัสไปรษณีย์',
        value: _draft.postalCode,
        digitsOnly: true,
        maxLength: 5,
        error: _errorFor('postalCode'),
        onChanged: (value) {
          _update('postalCode', () => _draft.setPostalCode(value));
          _formData.searchPostalCode(value);
        },
      ),
      AddressPicker(
        addresses: _formData.addresses,
        lookup: _formData.lookup,
        selected: _draft.address,
        error: _errorFor('addressChoice'),
        subdistrict: _draft.address?.subdistrict ?? '',
        district: _draft.address?.district ?? '',
        province: _draft.address?.province ?? '',
        onSelected: (value) =>
            _update('addressChoice', () => _draft.address = value),
      ),
    ];
  }

  List<Widget> _employmentFields() {
    return [
      _optionField(
        label: 'แผนก',
        kind: 'department',
        value: _draft.department,
        options: _formData.departments.map((item) => item.name).toList(),
        error: _errorFor('department'),
        onChanged: (value) =>
            _update('department', () => _draft.department = value),
      ),
      _optionField(
        label: 'ตำแหน่ง',
        kind: 'position',
        value: _draft.position,
        options: _formData.positions.map((item) => item.name).toList(),
        error: _errorFor('position'),
        onChanged: (value) => _update('position', () => _draft.position = value),
      ),
      AppDateField(
        label: 'วันเริ่มงาน',
        value: _draft.startDate,
        error: _errorFor('startDate'),
        onChanged: (value) => _update('startDate', () => _draft.startDate = value),
      ),
      if (_formData.optionsError != null)
        NoticeBox.error(
          text: _formData.optionsError!,
          onRetry: _formData.loadOptions,
        ),
    ];
  }

  /// ช่องเลือกแผนก/ตำแหน่ง พร้อมปุ่มเพิ่มตัวเลือกใหม่
  ///
  /// backend บังคับว่าค่าต้องมีอยู่ในตาราง employment_options ก่อน
  /// จึงต้องเพิ่มเข้าไปก่อนแล้วค่อยเลือก ไม่ใช่พิมพ์อิสระ
  Widget _optionField({
    required String label,
    required String kind,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    String? error,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppDropdownField<String>(
            label: label,
            value: value.isEmpty ? null : value,
            hint: _formData.optionsLoading ? 'กำลังโหลด...' : 'เลือก$label',
            error: error,
            enabled: options.isNotEmpty,
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (selected) => onChanged(selected ?? ''),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: IconButton.outlined(
            tooltip: 'เพิ่ม$label',
            icon: const Icon(Icons.add),
            onPressed: () => _addOption(label, kind, onChanged),
          ),
        ),
      ],
    );
  }

  Future<void> _addOption(
    String label,
    String kind,
    ValueChanged<String> onChanged,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('เพิ่ม$label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'ชื่อ$label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final created = await _formData.addOption(kind, name);
      onChanged(created.name);
    } on ApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.message)),
      );
    } catch (err) {
      debugPrint('Add employment option failed: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เพิ่ม$labelไม่สำเร็จ')),
      );
    }
  }

  Widget _buildSuccess(EmployeeRegistrationResult result) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลงทะเบียนสำเร็จ')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            result.employee.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'รหัสพนักงาน ${result.employee.employeeCode}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.amber.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.vpn_key, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'รหัสผ่านชั่วคราว',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    result.temporaryPassword,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'รหัสนี้แสดงครั้งเดียวเท่านั้น กรุณาจดและส่งให้พนักงาน '
                    'ก่อนออกจากหน้านี้ — ระบบไม่สามารถแสดงซ้ำได้อีก',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('เสร็จสิ้น'),
          ),
        ],
      ),
    );
  }
}
