import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/quran/quran_repository.dart';
import '../../data/repositories/demo_repository.dart';
import 'send_parents_sheet.dart';

class TeacherHomeScreen extends ConsumerWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final attendance = ref.watch(attendanceControllerProvider);
    final homework = ref.watch(homeworkControllerProvider);
    final quran = ref.watch(quranRepositoryProvider);
    final mosque = user == null
        ? null
        : ref.watch(demoRepositoryProvider).mosqueById(user.mosqueId);
    final dateLabel = DateFormat('EEEE d MMMM y', 'ar').format(DateTime.now());

    final presentCount =
        attendance.where((a) => a.status == AttendanceStatus.present).length;

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('لوحة المدرّس'),
          actions: [
            IconButton(
              tooltip: 'إدارة الطلبة',
              onPressed: () => context.push('/teacher/students'),
              icon: const Icon(Icons.groups_2_outlined),
            ),
            IconButton(
              onPressed: () {
                ref.read(authControllerProvider.notifier).logout();
                context.go('/welcome');
              },
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            FadeSlideIn(
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحبًا، ${user?.fullName ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(dateLabel),
                    const SizedBox(height: 4),
                    Text(
                      mosque?.name ?? '',
                      style: TextStyle(
                        color: AppColors.olive.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Row(
                children: [
                  Expanded(
                    child: _statTile(
                      context,
                      icon: 'assets/svg/icon_attendance.svg',
                      label: 'حاضرون',
                      value: '$presentCount/${attendance.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statTile(
                      context,
                      icon: 'assets/svg/icon_calendar.svg',
                      label: 'جلسة اليوم',
                      value: session == null ? 'لم تبدأ' : 'نشطة',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 110),
              child: GlassCard(
                onTap: () => context.push('/teacher/students'),
                child: const Row(
                  children: [
                    Icon(Icons.groups_2_outlined, color: AppColors.olive),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إدارة الطلبة والرموز',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'إضافة طالب وتوليد اسم مستخدم ورمز دخول',
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'جلسة اليوم',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(sessionControllerProvider.notifier).startToday();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تجهيز جدول درس اليوم')),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  session == null ? 'بدء محاضرة اليوم' : 'فتح محاضرة اليوم',
                ),
              ),
            ),
            if (session == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: GlassCard(
                  child: Text(
                    'ابدأ الجلسة لعرض الحضور ومستوى الحفظ والواجب الفردي لكل طالب.',
                  ),
                ),
              ),
            if (session != null) ...[
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 150),
                child: OutlinedButton.icon(
                  onPressed: attendance.isEmpty
                      ? null
                      : () => showSendParentsSheet(context, ref),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('إرسال التفاصيل لأولياء الأمور'),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'جدول الدرس',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'حضور ← مستوى الحفظ ← سلوك ← واجب فردي',
                style: TextStyle(
                  color: AppColors.ink.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 10),
              if (attendance.isEmpty)
                const GlassCard(
                  child: Text(
                    'لا يوجد طلبة في حلقتك. أضفهم من إدارة الطلبة.',
                  ),
                )
              else
                ...attendance.asMap().entries.map((entry) {
                  final i = entry.key;
                  final record = entry.value;
                  return FadeSlideIn(
                    delay: Duration(milliseconds: 160 + (i * 40)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LessonRow(
                        record: record,
                        homework: homework[record.studentId],
                        quran: quran,
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String icon,
    required String label,
    required String value,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgActionIcon(icon, size: 26),
          const SizedBox(height: 10),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.oliveDark,
                ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends ConsumerWidget {
  const _LessonRow({
    required this.record,
    required this.homework,
    required this.quran,
  });

  final AttendanceRecord record;
  final StudentHomework? homework;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attending = record.isAttending;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.softGreen,
                child: Text(
                  record.studentName.isEmpty ? '?' : record.studentName[0],
                  style: const TextStyle(
                    color: AppColors.oliveDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  record.studentName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'واتساب ولي الأمر',
                onPressed: () => showSendParentsSheet(
                  context,
                  ref,
                  onlyStudentId: record.studentId,
                ),
                icon: const Icon(Icons.chat_outlined, color: AppColors.olive),
              ),
              TextButton.icon(
                onPressed: () => _showAssignSheet(
                  context,
                  ref,
                  studentId: record.studentId,
                  studentName: record.studentName,
                  existing: homework,
                ),
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: const Text('واجب'),
              ),
            ],
          ),
          if (homework != null) ...[
            const SizedBox(height: 4),
            Text(
              'الواجب: ${quran.surahByNumber(homework!.surahNumber).name} '
              '${homework!.fromAyah}–${homework!.toAyah}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.olive.withValues(alpha: 0.9),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                label: 'حاضر',
                selected: record.status == AttendanceStatus.present,
                color: AppColors.success,
                onTap: () => ref
                    .read(attendanceControllerProvider.notifier)
                    .mark(record.studentId, AttendanceStatus.present),
              ),
              _chip(
                label: 'متأخر',
                selected: record.status == AttendanceStatus.late,
                color: AppColors.gold,
                onTap: () => ref
                    .read(attendanceControllerProvider.notifier)
                    .mark(record.studentId, AttendanceStatus.late),
              ),
              _chip(
                label: 'غائب',
                selected: record.status == AttendanceStatus.absent,
                color: AppColors.danger,
                onTap: () => ref
                    .read(attendanceControllerProvider.notifier)
                    .mark(record.studentId, AttendanceStatus.absent),
              ),
            ],
          ),
          if (attending) ...[
            const SizedBox(height: 14),
            const Text(
              'مستوى الحفظ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: MemorizationLevel.values.map((level) {
                final selected = record.memorizationLevel == level;
                return _chip(
                  label: level.labelAr,
                  selected: selected,
                  color: AppColors.olive,
                  onTap: () => ref
                      .read(attendanceControllerProvider.notifier)
                      .setMemorization(record.studentId, level),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'السلوك',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text(
                  '${record.behaviorScore ?? '-'} / 10',
                  style: const TextStyle(color: AppColors.oliveDark),
                ),
                Expanded(
                  child: Slider(
                    value: (record.behaviorScore ?? 5).toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: '${record.behaviorScore ?? 5}',
                    onChanged: (v) => ref
                        .read(attendanceControllerProvider.notifier)
                        .setBehavior(record.studentId, v.round()),
                  ),
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'مستوى الحفظ والسلوك يظهران عند الحضور أو التأخر فقط.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(minHeight: 36),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignSheet(
    BuildContext context,
    WidgetRef ref, {
    required String studentId,
    required String studentName,
    StudentHomework? existing,
  }) async {
    var surah = existing?.surahNumber ?? 2;
    var from = existing?.fromAyah ?? 1;
    var to = existing?.toAyah ?? 5;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final ayahCount = quran.surahByNumber(surah).ayahCount;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'واجب فردي — $studentName',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'كل طالب يسير بوتيرته؛ عيّن نطاق الحفظ المناسب له.',
                    style: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: surah,
                    decoration: const InputDecoration(labelText: 'السورة'),
                    items: quran.surahs
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.number,
                            child: Text('${s.number}. ${s.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() {
                        surah = v;
                        from = 1;
                        to = quran.surahByNumber(v).ayahCount.clamp(1, 15);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: from,
                          decoration:
                              const InputDecoration(labelText: 'من آية'),
                          items: List.generate(
                            ayahCount,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            ),
                          ),
                          onChanged: (v) =>
                              setModalState(() => from = v ?? 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: to.clamp(from, ayahCount),
                          decoration:
                              const InputDecoration(labelText: 'إلى آية'),
                          items: List.generate(
                            ayahCount,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            ),
                          ),
                          onChanged: (v) =>
                              setModalState(() => to = v ?? from),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        final safeTo = to < from ? from : to;
                        ref.read(homeworkControllerProvider.notifier).assign(
                              studentId: studentId,
                              surahNumber: surah,
                              fromAyah: from,
                              toAyah: safeTo,
                            );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم تعيين واجب لـ $studentName'),
                          ),
                        );
                      },
                      child: const Text('حفظ الواجب'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
