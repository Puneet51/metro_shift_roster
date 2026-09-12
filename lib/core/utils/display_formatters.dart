import 'package:intl/intl.dart';

String formatDisplayDate(String? value) {
  final raw = (value ?? '').trim();
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : DateFormat('dd/MM/yyyy').format(parsed);
}

String formatDisplayTime(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return raw;
  final parts = raw.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '');
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
  if (hour == null || minute == null) return raw;
  final dt = DateTime(2000, 1, 1, hour, minute);
  return DateFormat('h:mm a').format(dt);
}
