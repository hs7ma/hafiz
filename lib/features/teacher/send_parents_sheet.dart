import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/whatsapp_report.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/quran/quran_repository.dart';
import '../../data/repositories/demo_repository.dart';

class ParentReportTarget {
  const ParentReportTarget({
    required this.student,
    required this.record,
    required this.homework,
    required this.parentDigits,
  });

  final StudentProfile student;
  final AttendanceRecord record;
  final StudentHomework? homework;
  final String parentDigits;
}

/// ورقة إرسال تفاصيل الدرس لأولياء الأمور عبر واتساب (مجاني — wa.me).
Future<void> showSendParentsSheet(
  BuildContext context,
  WidgetRef ref, {
  String? onlyStudentId,
}) async {
  final user = ref.read(authControllerProvider);
  if (user == null || user.role != UserRole.teacher) return;

  final repo = ref.read(demoRepositoryProvider);
  final mosque = repo.mosqueById(user.mosqueId);
  final attendance = ref.read(attendanceControllerProvider);
  final homeworkMap = ref.read(homeworkControllerProvider);
  final quran = ref.read(quranRepositoryProvider);
  final students = repo.studentsForTeacher(user.id);

  if (attendance.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ابدأ جلسة اليوم أولاً ثم أرسل التفاصيل')),
    );
    return;
  }

  final countryCode = await loadTeacherCountryCode(user.id);
  final teacherWa = await loadTeacherWhatsApp(user.id) ?? '';

  final targets = <ParentReportTarget>[];
  final skipped = <String>[];

  for (final record in attendance) {
    if (onlyStudentId != null && record.studentId != onlyStudentId) continue;
    StudentProfile? student;
    for (final s in students) {
      if (s.id == record.studentId) {
        student = s;
        break;
      }
    }
    if (student == null) continue;
    final digits = toWhatsAppDigits(
      student.parentPhone,
      countryCode: countryCode,
    );
    if (!isPlausibleWhatsAppPhone(digits)) {
      skipped.add(student.fullName);
      continue;
    }
    targets.add(
      ParentReportTarget(
        student: student,
        record: record,
        homework: homeworkMap[student.id],
        parentDigits: digits,
      ),
    );
  }

  if (!context.mounted) return;

  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped.isEmpty
              ? 'لا يوجد طلبة لإرسال التفاصيل إليهم'
              : 'أرقام أولياء الأمور غير صالحة. راجعها من إدارة الطلبة.',
        ),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.ivory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return _SendParentsSheet(
        teacherId: user.id,
        teacherName: user.fullName,
        mosqueName: mosque?.name ?? '',
        initialTeacherWa: teacherWa,
        initialCountryCode: countryCode,
        targets: targets,
        skippedNames: skipped,
        quran: quran,
      );
    },
  );
}

class _SendParentsSheet extends StatefulWidget {
  const _SendParentsSheet({
    required this.teacherId,
    required this.teacherName,
    required this.mosqueName,
    required this.initialTeacherWa,
    required this.initialCountryCode,
    required this.targets,
    required this.skippedNames,
    required this.quran,
  });

  final String teacherId;
  final String teacherName;
  final String mosqueName;
  final String initialTeacherWa;
  final String initialCountryCode;
  final List<ParentReportTarget> targets;
  final List<String> skippedNames;
  final QuranRepository quran;

  @override
  State<_SendParentsSheet> createState() => _SendParentsSheetState();
}

class _SendParentsSheetState extends State<_SendParentsSheet> {
  late final TextEditingController _waCtrl;
  late final TextEditingController _ccCtrl;
  var _index = 0;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _waCtrl = TextEditingController(text: widget.initialTeacherWa);
    _ccCtrl = TextEditingController(text: widget.initialCountryCode);
  }

  @override
  void dispose() {
    _waCtrl.dispose();
    _ccCtrl.dispose();
    super.dispose();
  }

  Future<void> _persistTeacherSettings() async {
    await saveTeacherWhatsApp(widget.teacherId, _waCtrl.text);
    await saveTeacherCountryCode(widget.teacherId, _ccCtrl.text);
  }

  String _messageFor(ParentReportTarget t) {
    return buildParentLessonMessage(
      studentName: t.student.fullName,
      mosqueName: widget.mosqueName,
      teacherName: widget.teacherName,
      teacherWhatsAppDisplay: _waCtrl.text.trim(),
      record: t.record,
      homework: t.homework,
      quran: widget.quran,
    );
  }

  Future<void> _openCurrent() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _persistTeacherSettings();
    final t = widget.targets[_index];
    final ok = await openWhatsAppChat(
      phoneDigits: t.parentDigits,
      message: _messageFor(t),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _error = 'تعذّر فتح واتساب. تأكد من تثبيت التطبيق.';
      }
    });
  }

  Future<void> _openNext() async {
    if (_index >= widget.targets.length - 1) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _index += 1);
    await _openCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.targets[_index];
    final dateLabel = DateFormat('EEEE d MMMM y', 'ar').format(DateTime.now());
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'إرسال التفاصيل لأولياء الأمور',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'مجاني عبر واتساب على هاتفك. تفتح المحادثة برسالة جاهزة وتضغط إرسال.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 4),
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.olive.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _waCtrl,
              label: 'رقم واتساب المدرّس',
              hint: '05xxxxxxxx',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              prefixIcon: Icons.phone_outlined,
              onEditingComplete: () => _persistTeacherSettings(),
            ),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _ccCtrl,
              label: 'رمز الدولة (لأرقام تبدأ بـ 0)',
              hint: '966',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.flag_outlined,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onEditingComplete: () => _persistTeacherSettings(),
            ),
            const SizedBox(height: 8),
            Text(
              'رقمك يُذكر في الرسالة للاستفسار. الإرسال يتم من واتساب المثبّت على هذا الجهاز.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.ink.withValues(alpha: 0.55),
              ),
            ),
            if (widget.skippedNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'تُجاوز ${widget.skippedNames.length} طالبًا لرقم ولي أمر غير صالح: '
                  '${widget.skippedNames.join('، ')}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'الطالب ${_index + 1} من ${widget.targets.length}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current.student.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('ولي الأمر: ${current.student.parentPhone}'),
                  const SizedBox(height: 4),
                  Text(
                    'الحضور: ${attendanceLabelAr(current.record.status)}'
                    '${current.record.memorizationLevel != null ? ' · الحفظ: ${current.record.memorizationLevel!.labelAr}' : ''}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _messageFor(current),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.ink.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _openCurrent,
                icon: const Icon(Icons.chat_outlined),
                label: Text(
                  _index == 0 && !_busy
                      ? 'فتح واتساب لهذا الطالب'
                      : 'إعادة فتح واتساب',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (_index >= widget.targets.length - 1) {
                          await _persistTeacherSettings();
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        await _openNext();
                      },
                icon: Icon(
                  _index >= widget.targets.length - 1
                      ? Icons.check_rounded
                      : Icons.skip_next_rounded,
                ),
                label: Text(
                  _index >= widget.targets.length - 1
                      ? 'إنهاء'
                      : 'التالي (الطالب ${_index + 2})',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
