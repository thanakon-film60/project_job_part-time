import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/attendance_service.dart';

/// ชิ้นส่วน UI ที่หน้าจอใหม่ ๆ ใช้ร่วมกัน
///
/// รวมไว้ที่เดียวเพื่อให้ฟอร์มลงทะเบียน ฟอร์มแก้ไข และหน้าแฟ้มพนักงาน
/// หน้าตาเหมือนกันหมด — เหมือนที่ฝั่งเว็บใช้ components/ui ชุดเดียวกัน

/// การ์ดหัวข้อพร้อมไอคอน ใช้คุมทุกบล็อกเนื้อหาให้เว้นระยะเท่ากัน
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  /// ปุ่ม/ตัวบ่งชี้มุมขวาบนของหัวข้อ (เช่น ปุ่มโหลดใหม่)
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// บรรทัด "หัวข้อ: ค่า" ในแฟ้มพนักงาน
class InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const InfoRow({super.key, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final text = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? 'ยังไม่ระบุ' : text,
              style: TextStyle(
                fontSize: 13,
                color: text.isEmpty ? Colors.black38 : Colors.black87,
                fontWeight: text.isEmpty ? FontWeight.normal : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ตัวเลขสรุปหนึ่งช่อง (แทน StatCard ของเว็บ)
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final Color? tone;

  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    suffix!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// กล่องข้อความบอกสถานะ (กำลังโหลด / ว่างเปล่า / ผิดพลาด)
class NoticeBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onRetry;

  const NoticeBox({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.onRetry,
  });

  const NoticeBox.loading({super.key, this.text = 'กำลังโหลดข้อมูล...'})
      : icon = Icons.hourglass_empty,
        color = Colors.black45,
        onRetry = null;

  const NoticeBox.empty({super.key, required this.text})
      : icon = Icons.inbox,
        color = Colors.black45,
        onRetry = null;

  const NoticeBox.error({super.key, required this.text, this.onRetry})
      : icon = Icons.wifi_off,
        color = Colors.redAccent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: color))),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('ลองใหม่'),
            ),
          ],
        ],
      ),
    );
  }
}

/// ป้ายสีสั้น ๆ (แทน Badge ของเว็บ)
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const Tag({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ช่องกรอกข้อความพร้อมป้ายชื่อและข้อความผิดพลาดใต้ช่อง
class AppTextField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? error;
  final String? hint;
  final TextInputType? keyboardType;
  final int? maxLength;

  /// รับเฉพาะตัวเลข — ใช้กับเลขบัตร เบอร์โทร รหัสไปรษณีย์
  final bool digitsOnly;
  final bool enabled;
  final bool readOnly;

  const AppTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.error,
    this.hint,
    this.keyboardType,
    this.maxLength,
    this.digitsOnly = false,
    this.enabled = true,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        enabled: enabled,
        readOnly: readOnly,
        keyboardType:
            keyboardType ?? (digitsOnly ? TextInputType.number : null),
        maxLength: maxLength,
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          counterText: '',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

/// ช่องเลือกวันที่ — เปิด date picker ของระบบ
class AppDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? error;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.error,
    this.firstDate,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: selected ?? now,
            firstDate: firstDate ?? DateTime(now.year - 80),
            lastDate: lastDate ?? DateTime(now.year + 5),
          );
          if (picked != null) {
            onChanged(DateTime(picked.year, picked.month, picked.day));
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(
            selected == null ? 'เลือกวันที่' : thaiLongDate(selected),
            style: TextStyle(
              color: selected == null ? Colors.black38 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

/// ช่องเลือกจากรายการ
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? error;
  final String? hint;
  final bool enabled;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.error,
    this.hint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: enabled ? onChanged : null,
        isExpanded: true,
        hint: hint == null ? null : Text(hint!),
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
