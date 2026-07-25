import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/models.dart';

String _statusAr(AttendanceStatus s) => switch (s) {
      AttendanceStatus.present => 'حاضر',
      AttendanceStatus.absent => 'غائب',
      AttendanceStatus.late => 'متأخر',
      AttendanceStatus.unmarked => 'غير محدد',
    };

/// يبني ملف Excel احترافي لأرشيف الدروس ويشاركه.
Future<void> exportLessonArchiveExcel({
  required String teacherName,
  required String mosqueName,
  required DateTime from,
  required DateTime to,
  required String periodLabel,
  required List<LessonArchiveRow> rows,
}) async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null) {
    excel.rename(defaultSheet, 'أرشيف الدروس');
  }
  final sheet = excel['أرشيف الدروس'];

  final titleStyle = CellStyle(
    bold: true,
    fontSize: 14,
    horizontalAlign: HorizontalAlign.Center,
  );
  final headerStyle = CellStyle(
    bold: true,
    fontSize: 11,
    horizontalAlign: HorizontalAlign.Center,
  );
  final cellStyle = CellStyle(
    fontSize: 11,
    horizontalAlign: HorizontalAlign.Center,
  );

  final dateFmt = DateFormat('yyyy/MM/dd', 'ar');
  final rangeLabel =
      '${dateFmt.format(from)} — ${dateFmt.format(to)} ($periodLabel)';

  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0),
  );
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .value = TextCellValue('أرشيف دروس حلقة التحفيظ — حافظ');
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .cellStyle = titleStyle;

  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
      .value = TextCellValue('المسجد: $mosqueName');
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
      .value = TextCellValue('المدرّس: $teacherName');
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
      .value = TextCellValue('الفترة: $rangeLabel');

  const headers = [
    'التاريخ',
    'اسم الطالب',
    'الحضور',
    'مستوى الحفظ',
    'السلوك',
    'معرّف الجلسة',
  ];
  for (var i = 0; i < headers.length; i++) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
    cell.value = TextCellValue(headers[i]);
    cell.cellStyle = headerStyle;
  }

  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final values = [
      dateFmt.format(row.sessionDate),
      row.studentName,
      _statusAr(row.status),
      row.memorizationLevel?.labelAr ?? '—',
      row.behaviorScore?.toString() ?? '—',
      row.sessionId,
    ];
    for (var c = 0; c < values.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 6 + r),
      );
      cell.value = TextCellValue(values[c]);
      cell.cellStyle = cellStyle;
    }
  }

  sheet.setColumnWidth(0, 14);
  sheet.setColumnWidth(1, 22);
  sheet.setColumnWidth(2, 12);
  sheet.setColumnWidth(3, 14);
  sheet.setColumnWidth(4, 10);
  sheet.setColumnWidth(5, 36);

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('تعذّر إنشاء ملف Excel');
  }

  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
  final file = File('${dir.path}/hafiz_archive_$stamp.xlsx');
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
    subject: 'أرشيف دروس حافظ — $periodLabel',
    text: 'أرشيف دروس حلقة $teacherName ($rangeLabel)',
  );
}
