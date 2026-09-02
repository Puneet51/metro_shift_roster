import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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
    final endDate = DateFormat('yyyy-MM-$daysInMonth').format(selectedMonth);

    final isPersonalReport = operatorId != null && operatorId.trim().isNotEmpty;

    // 1. Fetch Completed Attendance Records
    var attQuery = client
        .from('attendance')
        .select('''
          operator_id,
          duty_date,
          punch_in_time,
          punch_out_time,
          duty_duration_seconds,
          status,
          stations(id, name),
          profiles!inner(
            id,
            full_name,
            role,
            emp_code,
            company_id,
            biometric_id,
            bmrcl_id,
            father_name,
            doj,
            esi_no,
            uan_no
          )
        ''')
        .gte('duty_date', startDate)
        .lte('duty_date', endDate)
        .not('punch_in_time', 'is', null)
        .not('punch_out_time', 'is', null);

    if (stationId.isNotEmpty && stationId != 'all') {
      attQuery = attQuery.eq('station_id', stationId);
    }
    if (isPersonalReport) {
      attQuery = attQuery.eq('operator_id', operatorId);
    }

    final attendanceRes = await attQuery;

    final Map<String, Map<String, dynamic>> staffMap = {};
    final Map<String, Map<int, String>> attendanceMap = {};

    for (final row in (attendanceRes as List)) {
      final p = row['profiles'] as Map<String, dynamic>;
      final opId = p['id'] as String;
      staffMap.putIfAbsent(opId, () => p);

      final dutyDateStr = row['duty_date'] as String;
      final date = DateTime.parse(dutyDateStr);
      final status = (row['status'] ?? '').toString().toLowerCase();
      final duration = (row['duty_duration_seconds'] as num?)?.toInt() ?? 0;
      final role = (p['role'] ?? 'operator').toString().toLowerCase();

      final isPresent =
          status == 'present' || duration >= 28200 || role == 'supervisor';

      if (isPresent) {
        attendanceMap.putIfAbsent(opId, () => {});
        attendanceMap[opId]![date.day] = 'P';
      }
    }

    // 2. Fetch Supervisor Attendance ONLY if this is a station-wide supervisor export
    if (!isPersonalReport) {
      var supQuery = client
          .from('attendance')
          .select('''
            operator_id,
            duty_date,
            punch_in_time,
            punch_out_time,
            status,
            profiles!inner(
              id,
              full_name,
              role,
              emp_code,
              company_id,
              biometric_id,
              bmrcl_id,
              father_name,
              doj,
              esi_no,
              uan_no
            )
          ''')
          .gte('duty_date', startDate)
          .lte('duty_date', endDate)
          .eq('profiles.role', 'supervisor')
          .not('punch_in_time', 'is', null)
          .not('punch_out_time', 'is', null);

      if (stationId.isNotEmpty && stationId != 'all') {
        supQuery = supQuery.eq('station_id', stationId);
      }

      final supervisorRes = await supQuery;
      for (final row in (supervisorRes as List)) {
        final p = row['profiles'] as Map<String, dynamic>;
        final supId = p['id'] as String;
        staffMap.putIfAbsent(supId, () => p);

        final dutyDateStr = row['duty_date'] as String;
        final date = DateTime.parse(dutyDateStr);
        attendanceMap.putIfAbsent(supId, () => {});
        attendanceMap[supId]![date.day] = 'P';
      }
    }

    // Fallback: If operator had no attendance this month, still show their profile row
    if (isPersonalReport && staffMap.isEmpty) {
      final userProfile = await client
          .from('profiles')
          .select()
          .eq('id', operatorId)
          .maybeSingle();
      if (userProfile != null) {
        staffMap[operatorId] = userProfile;
      }
    }

    // Sort: Supervisors first, then alphabetically
    final List<Map<String, dynamic>> allStaff = staffMap.values.toList()
      ..sort((a, b) {
        final roleA = (a['role'] ?? '').toString().toLowerCase();
        final roleB = (b['role'] ?? '').toString().toLowerCase();
        if (roleA == 'supervisor' && roleB != 'supervisor') return -1;
        if (roleA != 'supervisor' && roleB == 'supervisor') return 1;
        return (a['full_name'] ?? '').toString().compareTo(
          (b['full_name'] ?? '').toString(),
        );
      });

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
    sheet.appendRow([TextCellValue('Designation: TOM OPERATOR')]);
    sheet.appendRow([TextCellValue('')]);

    // Headers
    final List<CellValue> tableHeaderRow = [
      TextCellValue('SL NO'),
      TextCellValue('Role'),
      TextCellValue('Emp Code'),
      TextCellValue('Biometric ID'),
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
      final role = (staff['role'] ?? 'operator').toString().toUpperCase();
      int totalPresent = 0;

      final empCodeVal = staff['emp_code'] ?? staff['company_id'] ?? '-';
      final bioIdVal = staff['biometric_id'] ?? staff['bmrcl_id'] ?? '-';

      final List<CellValue> row = [
        IntCellValue(i + 1),
        TextCellValue(role),
        TextCellValue(empCodeVal.toString()),
        TextCellValue(bioIdVal.toString()),
        TextCellValue((staff['full_name'] ?? '-').toString()),
        TextCellValue((staff['father_name'] ?? '-').toString()),
        TextCellValue((staff['doj'] ?? '-').toString()),
        TextCellValue((staff['esi_no'] ?? '-').toString()),
        TextCellValue((staff['uan_no'] ?? '-').toString()),
      ];

      for (int d = 1; d <= daysInMonth; d++) {
        final status = staffAtt[d];
        if (status == 'P') {
          totalPresent++;
          dailyPresentCount[d] = (dailyPresentCount[d] ?? 0) + 1;
          row.add(TextCellValue('P'));
        } else {
          row.add(TextCellValue('-'));
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
