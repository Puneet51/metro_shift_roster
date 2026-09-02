import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import '../../features/staff/data/operator_model.dart';

class ExcelExportService {
  /// Generates clean attendance sheet filtered by station
  static Future<String> generateStationAttendanceReport({
    required String stationName,
    required List<OperatorModel> staffList,
    required Map<String, int> presentCounts,
    required Map<String, int> otCounts,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = '$stationName Attendance';

    // Headers
    sheet.getRangeByName('A1').setText('SL No');
    sheet.getRangeByName('B1').setText('TOM Operator Name');
    sheet.getRangeByName('C1').setText('Biometric ID');
    sheet.getRangeByName('D1').setText('Company ID');
    sheet.getRangeByName('E1').setText('BMRCL ID');
    sheet.getRangeByName('F1').setText('Total Duty Present');
    sheet.getRangeByName('G1').setText('Total OT');

    final headerRange = sheet.getRangeByName('A1:G1');
    headerRange.cellStyle.bold = true;
    headerRange.cellStyle.backColor = '#1E3A8A';
    headerRange.cellStyle.fontColor = '#FFFFFF';

    // Populate rows
    for (int i = 0; i < staffList.length; i++) {
      final op = staffList[i];
      final row = i + 2;
      sheet.getRangeByName('A$row').setNumber((i + 1).toDouble());
      sheet.getRangeByName('B$row').setText(op.fullName);
      sheet.getRangeByName('C$row').setText(op.biometricId ?? 'N/A');
      sheet.getRangeByName('D$row').setText(op.companyId ?? 'N/A');
      sheet.getRangeByName('E$row').setText(op.bmrclId ?? 'N/A');
      sheet
          .getRangeByName('F$row')
          .setNumber((presentCounts[op.id] ?? 0).toDouble());
      sheet
          .getRangeByName('G$row')
          .setNumber((otCounts[op.id] ?? 0).toDouble());
    }

    sheet.autoFitColumn(1);
    sheet.autoFitColumn(2);
    sheet.autoFitColumn(3);
    sheet.autoFitColumn(4);
    sheet.autoFitColumn(5);

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/${stationName}_attendance_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    return path;
  }
}
