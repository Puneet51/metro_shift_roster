import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import '../../features/staff/data/operator_model.dart';

class ExcelExportService {
  /// Generates clean attendance sheet filtered by station with complete statutory details
  static Future<String> generateStationAttendanceReport({
    required String stationName,
    required List<OperatorModel> staffList,
    required Map<String, int> presentCounts,
  }) async {
    final xls.Workbook workbook = xls.Workbook();
    final xls.Worksheet sheet = workbook.worksheets[0];
    sheet.name = '$stationName Attendance';

    // Form 'T' & Statutory Headers
    final List<String> headers = [
      'SL No',
      'TOM Operator Name',
      "Father's Name",
      'Emp Code',
      'Biometric ID',
      'BMRCL ID',
      'DOJ',
      'ESI Number',
      'UAN Number',
      'Total Duty Present',
    ];

    for (int col = 0; col < headers.length; col++) {
      sheet.getRangeByIndex(1, col + 1).setText(headers[col]);
    }

    final headerRange = sheet.getRangeByIndex(1, 1, 1, headers.length);
    headerRange.cellStyle.bold = true;
    headerRange.cellStyle.backColor = '#1E3A8A';
    headerRange.cellStyle.fontColor = '#FFFFFF';

    // Populate rows
    for (int i = 0; i < staffList.length; i++) {
      final op = staffList[i];
      final row = i + 2;

      sheet.getRangeByName('A$row').setNumber((i + 1).toDouble());
      sheet
          .getRangeByName('B$row')
          .setText(op.fullName.isNotEmpty ? op.fullName : '-');
      sheet
          .getRangeByName('C$row')
          .setText(op.fatherName?.isNotEmpty == true ? op.fatherName! : '-');
      sheet
          .getRangeByName('D$row')
          .setText(op.empCode?.isNotEmpty == true ? op.empCode! : '-');
      sheet
          .getRangeByName('E$row')
          .setText(op.biometricId?.isNotEmpty == true ? op.biometricId! : '-');
      sheet
          .getRangeByName('F$row')
          .setText(op.bmrclId?.isNotEmpty == true ? op.bmrclId! : '-');
      sheet
          .getRangeByName('G$row')
          .setText(op.doj?.isNotEmpty == true ? op.doj! : '-');
      sheet
          .getRangeByName('H$row')
          .setText(op.esiNo?.isNotEmpty == true ? op.esiNo! : '-');
      sheet
          .getRangeByName('I$row')
          .setText(op.uanNo?.isNotEmpty == true ? op.uanNo! : '-');
      sheet
          .getRangeByName('J$row')
          .setNumber((presentCounts[op.id] ?? 0).toDouble());
    }

    for (int col = 1; col <= headers.length; col++) {
      sheet.autoFitColumn(col);
    }

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
