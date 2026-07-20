import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/models.dart';
import '../../data/quran/quran_repository.dart';

const _kTeacherWaPrefix = 'hafiz_teacher_wa_';
const _kTeacherCcPrefix = 'hafiz_teacher_cc_';

/// رمز الدولة الافتراضي لأرقام تبدأ بـ 0 (مثل 05xxxxxxxx).
const defaultCountryCode = '966';

String attendanceLabelAr(AttendanceStatus status) => switch (status) {
      AttendanceStatus.present => 'حاضر',
      AttendanceStatus.late => 'متأخر',
      AttendanceStatus.absent => 'غائب',
      AttendanceStatus.unmarked => 'لم يُحدَّد',
    };

/// يحوّل رقم الهاتف إلى صيغة واتساب الدولية (أرقام فقط بدون +).
String toWhatsAppDigits(
  String raw, {
  String countryCode = defaultCountryCode,
}) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) {
    d = '$countryCode${d.substring(1)}';
  }
  return d;
}

bool isPlausibleWhatsAppPhone(String digits) =>
    digits.length >= 10 && digits.length <= 15;

Future<String?> loadTeacherWhatsApp(String teacherId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('$_kTeacherWaPrefix$teacherId');
}

Future<void> saveTeacherWhatsApp(String teacherId, String phone) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('$_kTeacherWaPrefix$teacherId', phone.trim());
}

Future<String> loadTeacherCountryCode(String teacherId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('$_kTeacherCcPrefix$teacherId') ?? defaultCountryCode;
}

Future<void> saveTeacherCountryCode(String teacherId, String code) async {
  final prefs = await SharedPreferences.getInstance();
  final cleaned = code.replaceAll(RegExp(r'\D'), '');
  await prefs.setString(
    '$_kTeacherCcPrefix$teacherId',
    cleaned.isEmpty ? defaultCountryCode : cleaned,
  );
}

String buildParentLessonMessage({
  required String studentName,
  required String mosqueName,
  required String teacherName,
  required String teacherWhatsAppDisplay,
  required AttendanceRecord record,
  required StudentHomework? homework,
  required QuranRepository quran,
  DateTime? date,
}) {
  final day = DateFormat('EEEE d MMMM y', 'ar').format(date ?? DateTime.now());
  final lines = <String>[
    'السلام عليكم ولي أمر الطالب *$studentName*',
    '',
    'تفاصيل درس اليوم ($day)',
    'المسجد: $mosqueName',
    'المدرّس: $teacherName',
    '',
    'الحضور: ${attendanceLabelAr(record.status)}',
  ];

  if (record.isAttending) {
    lines.add(
      'مستوى الحفظ: ${record.memorizationLevel?.labelAr ?? 'لم يُقيَّم'}',
    );
    lines.add(
      'السلوك: ${record.behaviorScore != null ? '${record.behaviorScore}/10' : 'لم يُقيَّم'}',
    );
  }

  if (homework != null) {
    final surah = quran.surahByNumber(homework.surahNumber).name;
    lines.add('الواجب: $surah ${homework.fromAyah}–${homework.toAyah}');
    if (homework.note.trim().isNotEmpty) {
      lines.add('ملاحظة: ${homework.note.trim()}');
    }
  } else {
    lines.add('الواجب: لم يُعيَّن بعد');
  }

  if (teacherWhatsAppDisplay.trim().isNotEmpty) {
    lines.add('');
    lines.add('للاستفسار يمكنكم التواصل مع المدرّس على واتساب: $teacherWhatsAppDisplay');
  }

  lines.add('');
  lines.add('— تطبيق حافظ');
  return lines.join('\n');
}

Uri whatsAppUri({required String phoneDigits, required String message}) {
  return Uri.parse(
    'https://wa.me/$phoneDigits?text=${Uri.encodeComponent(message)}',
  );
}

Future<bool> openWhatsAppChat({
  required String phoneDigits,
  required String message,
}) async {
  final uri = whatsAppUri(phoneDigits: phoneDigits, message: message);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
