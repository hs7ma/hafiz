import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/demo_repository.dart';

class TeacherSettingsScreen extends ConsumerWidget {
  const TeacherSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(classScheduleControllerProvider);
    final upcoming =
        ref.watch(demoRepositoryProvider).upcomingLectureDates(count: 4);
    final dateFmt = DateFormat('EEEE d MMMM', 'ar');

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('إعدادات المدرّس'),
          leading: const AppBackButton(fallback: '/teacher'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            FadeSlideIn(
              child: GlassCard(
                onTap: () => context.push('/teacher/settings/schedule'),
                child: const Row(
                  children: [
                    Icon(Icons.event_repeat_outlined, color: AppColors.olive),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ضبط مواعيد الدروس',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'حدد عدد المحاضرات الأسبوعية وأيام الحلقة',
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: GlassCard(
                onTap: () => context.push('/teacher/archive'),
                child: const Row(
                  children: [
                    Icon(Icons.history_edu_outlined, color: AppColors.olive),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أرشيف الدروس',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'عرض أسبوعي وشهري وسنوي مع تصدير Excel',
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ملخص المواعيد',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: const Duration(milliseconds: 100),
              child: GlassCard(
                child: schedule == null || !schedule.active
                    ? const Text(
                        'لم يُضبط جدول بعد. ادخل «ضبط مواعيد الدروس» لتحديد أيام الحلقة.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${schedule.lecturesPerWeek} محاضرات أسبوعيًا',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            schedule.weekdays
                                .map((d) => arabicWeekdayLabels[d] ?? '$d')
                                .join(' · '),
                            style: TextStyle(
                              color: AppColors.olive.withValues(alpha: 0.95),
                            ),
                          ),
                          if (upcoming.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'المحاضرات القادمة',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            ...upcoming.map(
                              (d) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• ${dateFmt.format(d)}'),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TeacherScheduleEditorScreen extends ConsumerStatefulWidget {
  const TeacherScheduleEditorScreen({super.key});

  @override
  ConsumerState<TeacherScheduleEditorScreen> createState() =>
      _TeacherScheduleEditorScreenState();
}

class _TeacherScheduleEditorScreenState
    extends ConsumerState<TeacherScheduleEditorScreen> {
  late int _lectures;
  late Set<int> _selectedDays;

  static const _dayOrder = [6, 7, 1, 2, 3, 4, 5]; // سبت…جمعة

  @override
  void initState() {
    super.initState();
    final existing = ref.read(classScheduleControllerProvider);
    _lectures = existing?.lecturesPerWeek ?? 3;
    _selectedDays = {...(existing?.weekdays ?? const <int>[])};
  }

  @override
  Widget build(BuildContext context) {
    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('ضبط مواعيد الدروس'),
          leading: const AppBackButton(fallback: '/teacher/settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'عدد المحاضرات الأسبوعية',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var n = 1; n <= 7; n++)
                        ChoiceChip(
                          label: Text('$n'),
                          selected: _lectures == n,
                          onSelected: (_) {
                            setState(() {
                              _lectures = n;
                              if (_selectedDays.length > n) {
                                _selectedDays = _selectedDays
                                    .take(n)
                                    .toSet();
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أيام المحاضرات (اختر $_lectures)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in _dayOrder)
                        FilterChip(
                          label: Text(arabicWeekdayLabels[day]!),
                          selected: _selectedDays.contains(day),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                if (_selectedDays.length >= _lectures) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'اختر $_lectures أيام فقط — زد العدد أولًا إن لزم',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _selectedDays.add(day);
                              } else {
                                _selectedDays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final err = await ref
                    .read(classScheduleControllerProvider.notifier)
                    .save(
                      lecturesPerWeek: _lectures,
                      weekdays: _selectedDays.toList(),
                    );
                if (!context.mounted) return;
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حفظ مواعيد الدروس')),
                );
                context.pop();
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ المواعيد'),
            ),
          ],
        ),
      ),
    );
  }
}
