import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/core/utils/display_formatters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:open_filex/open_filex.dart';

class FormTExcelGenerator {
  static Future<void> generateAndDownloadExcel({
    required String stationId,
    required String stationName,
    required DateTime selectedMonth,
    String? operatorId,
  }) async {
    final client = Supabase.instance.client;
    final year = selectedMonth.year;
    final month = selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final formattedMonth = DateFormat('MMMM yyyy').format(selectedMonth);

    final startDate = DateFormat('yyyy-MM-01').format(selectedMonth);
    final nextMonth = DateTime(year, month + 1, 1);
    final nextMonthDate = DateFormat('yyyy-MM-01').format(nextMonth);

    final isPersonalReport = operatorId != null && operatorId.trim().isNotEmpty;

    // Build the report from actual assignments. This makes Excel update as soon as
    // the shift has actually finished, even before a background attendance
    // finalizer has written the attendance row.
    var assignmentQuery = client.from('shift_assignments').select("""
          operator_id,
          station_id,
          is_ot,
          shifts!inner(
            id, duty_date, shift_name, start_time, end_time, is_published
          ),
          profiles!inner(
            id, full_name, role, emp_code, company_id, biometric_id,
            bmrcl_id, father_name, doj, esi_no, uan_no
          )
        """).eq('shifts.is_published', true)
        .eq('profiles.role', 'operator')
        .gte('shifts.duty_date', startDate)
        .lt('shifts.duty_date', nextMonthDate);

    if (stationId.trim().isNotEmpty && stationId != 'all') {
      assignmentQuery = assignmentQuery.eq('station_id', stationId);
    }
    if (isPersonalReport && operatorId != null) {
      assignmentQuery = assignmentQuery.eq('operator_id', operatorId);
    }

    final assignmentRes = await assignmentQuery;
    final now = DateTime.now();

    final Map<String, Map<String, dynamic>> staffMap = {};
    final Map<String, Map<int, String>> attendanceMap = {};

    DateTime completedAt(String dutyDate, String? start, String? end) {
      final d = DateTime.tryParse(dutyDate);
      if (d == null) return DateTime(9999);
      final sp = (start ?? '00:00:00').split(':');
      final ep = (end ?? '00:00:00').split(':');
      final sh = int.tryParse(sp.isNotEmpty ? sp[0] : '0') ?? 0;
      final sm = int.tryParse(sp.length > 1 ? sp[1] : '0') ?? 0;
      final eh = int.tryParse(ep.isNotEmpty ? ep[0] : '0') ?? 0;
      final em = int.tryParse(ep.length > 1 ? ep[1] : '0') ?? 0;
      var result = DateTime(d.year, d.month, d.day, eh, em);
      if (eh * 60 + em < sh * 60 + sm) result = result.add(const Duration(days: 1));
      return result;
    }

    for (final raw in (assignmentRes as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final shift = row['shifts'] is Map
          ? Map<String, dynamic>.from(row['shifts'] as Map)
          : <String, dynamic>{};
      final profile = row['profiles'] is Map
          ? Map<String, dynamic>.from(row['profiles'] as Map)
          : <String, dynamic>{};
      final dutyDateStr = shift['duty_date']?.toString() ?? '';
      if (dutyDateStr.isEmpty || now.isBefore(completedAt(
            dutyDateStr, shift['start_time']?.toString(), shift['end_time']?.toString()))) continue;

      final opId = profile['id']?.toString() ?? row['operator_id']?.toString() ?? '';
      if (opId.isEmpty) continue;
      staffMap[opId] = profile;
      final date = DateTime.tryParse(dutyDateStr);
      if (date == null) continue;
      attendanceMap.putIfAbsent(opId, () => {});
      // OT is displayed exactly like a normal completed duty.
      attendanceMap[opId]![date.day] = 'P';
    }

    // Sort alphabetically by employee name.
    final List<Map<String, dynamic>> allStaff = staffMap.values.toList()
      ..sort((a, b) => (a['full_name'] ?? '').toString().compareTo(
            (b['full_name'] ?? '').toString(),
          ));

    // 3. Build Excel
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'TOM Operator Attendance');
    final sheet = excel['TOM Operator Attendance'];

    final headerTitle = isPersonalReport
        ? 'TOM OPERATOR PERSONAL ATTENDANCE'
        : 'TOM OPERATOR ATTENDANCE';

    sheet.appendRow([TextCellValue(headerTitle)]);
    sheet.appendRow([TextCellValue('Station: $stationName')]);
    sheet.appendRow([TextCellValue('Month: $formattedMonth')]);
    sheet.appendRow([TextCellValue(isPersonalReport ? 'Designation: TOM OPERATOR' : 'Designation: OPERATOR / SUPERVISOR')]);
    sheet.appendRow([TextCellValue('')]);

    // Form 'T' Matching Statutory Headers
    final List<CellValue> tableHeaderRow = [
      TextCellValue('SL NO'),
      TextCellValue('Emp Code'),
      TextCellValue('Biometric ID'),
      TextCellValue('BMRCL ID'),
      TextCellValue('Names'),
      TextCellValue("Father's Name"),
      TextCellValue('DOJ'),
      TextCellValue('ESI'),
      TextCellValue('UAN'),
      for (int d = 1; d <= daysInMonth; d++) TextCellValue('$d'),
      TextCellValue('TOTAL'),
    ];
    sheet.appendRow(tableHeaderRow);

    final Map<int, int> dailyPresentCount = {};
    int grandTotalCount = 0;

    for (int i = 0; i < allStaff.length; i++) {
      final staff = allStaff[i];
      final staffId = staff['id'];
      final staffAtt = attendanceMap[staffId] ?? {};
      int totalPresent = 0;

      final empCodeVal = (staff['emp_code'] ?? staff['company_id'] ?? '-')
          .toString();
      final bioIdVal = (staff['biometric_id'] ?? '-').toString();
      final bmrclIdVal = (staff['bmrcl_id'] ?? '-').toString();
      final fatherVal = (staff['father_name'] ?? '-').toString();
      final dojVal = formatDisplayDate(staff['doj']?.toString());
      final esiVal = (staff['esi_no'] ?? '-').toString();
      final uanVal = (staff['uan_no'] ?? '-').toString();

      final List<CellValue> row = [
        IntCellValue(i + 1),
        TextCellValue(empCodeVal.isNotEmpty ? empCodeVal : '-'),
        TextCellValue(bioIdVal.isNotEmpty ? bioIdVal : '-'),
        TextCellValue(bmrclIdVal.isNotEmpty ? bmrclIdVal : '-'),
        TextCellValue((staff['full_name'] ?? '-').toString()),
        TextCellValue(fatherVal.isNotEmpty ? fatherVal : '-'),
        TextCellValue(dojVal.isNotEmpty ? dojVal : '-'),
        TextCellValue(esiVal.isNotEmpty ? esiVal : '-'),
        TextCellValue(uanVal.isNotEmpty ? uanVal : '-'),
      ];

      for (int d = 1; d <= daysInMonth; d++) {
        final status = staffAtt[d];
        if (status == 'P') {
          totalPresent++;
          dailyPresentCount[d] = (dailyPresentCount[d] ?? 0) + 1;
          row.add(TextCellValue('P'));
        } else if (status == 'A') {
          row.add(TextCellValue('A'));
        } else {
          row.add(TextCellValue('A'));
        }
      }

      grandTotalCount += totalPresent;
      row.add(IntCellValue(totalPresent));
      sheet.appendRow(row);
    }

    // Grand Total Row
    final List<CellValue> grandTotalRow = [
      TextCellValue('GRAND TOTAL'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
      TextCellValue('-'),
    ];

    for (int d = 1; d <= daysInMonth; d++) {
      grandTotalRow.add(IntCellValue(dailyPresentCount[d] ?? 0));
    }
    grandTotalRow.add(IntCellValue(grandTotalCount));
    sheet.appendRow(grandTotalRow);

    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([
      TextCellValue('SC NAME & EMPLOYEE CODE:'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('SIGN & SEAL:'),
    ]);

    final fileBytes = excel.save();
    final cleanStationName = stationName
        .replaceAll(RegExp(r'[^\w\s]+'), '_')
        .replaceAll(' ', '_');
    final cleanMonth = DateFormat('MMM_yyyy').format(selectedMonth);

    final String fileName;
    if (isPersonalReport) {
      final cleanOpName =
          (allStaff.isNotEmpty ? allStaff.first['full_name'] ?? 'My' : 'My')
              .toString()
              .replaceAll(' ', '_');
      fileName =
          'Attendance_${cleanOpName}_${cleanStationName}_$cleanMonth.xlsx';
    } else {
      fileName = 'TOM_Operator_Attendance_${cleanStationName}_$cleanMonth.xlsx';
    }

    if (fileBytes != null) {
      if (kIsWeb) {
        final blob = html.Blob([fileBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(fileBytes, flush: true);
        await OpenFilex.open(file.path);
      }
    }
  }
}
