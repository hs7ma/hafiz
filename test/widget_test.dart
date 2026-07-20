import 'package:flutter_test/flutter_test.dart';

import 'package:hafiz/core/utils/code_generators.dart';
import 'package:hafiz/core/utils/whatsapp_report.dart';
import 'package:hafiz/data/models/models.dart';

void main() {
  test('AttendanceStatus values exist for teacher marking', () {
    expect(AttendanceStatus.values.length, 4);
    expect(UserRole.mosqueAdmin.name, 'mosqueAdmin');
    expect(MemorizationLevel.values.length, 6);
  });

  test('teacher code is two letters plus six digits', () {
    final codes = CodeGenerators();
    final code = codes.teacherCode('Ibrahim');
    expect(code.length, 8);
    expect(code.substring(0, 2), 'IB');
    expect(RegExp(r'^\d{6}$').hasMatch(code.substring(2)), isTrue);
  });

  test('student code length is 5 to 8', () {
    final codes = CodeGenerators();
    for (var i = 0; i < 20; i++) {
      final code = codes.studentCode();
      expect(code.length, inInclusiveRange(5, 8));
    }
  });

  test('WhatsApp phone normalization', () {
    expect(toWhatsAppDigits('0511111111'), '966511111111');
    expect(toWhatsAppDigits('+966 51 111 1111'), '966511111111');
    expect(toWhatsAppDigits('00966511111111'), '966511111111');
    expect(isPlausibleWhatsAppPhone('966511111111'), isTrue);
    expect(isPlausibleWhatsAppPhone('123'), isFalse);
  });
}
