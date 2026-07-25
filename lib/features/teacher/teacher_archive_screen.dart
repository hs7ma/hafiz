import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/lesson_archive_excel.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/demo_repository.dart';

enum ArchivePeriod { weekly, monthly, yearly }

class TeacherArchiveScreen extends ConsumerStatefulWidget {
  const TeacherArchiveScreen({super.key});

  @override
  ConsumerState<TeacherArchiveScreen> createState() =>
      _TeacherArchiveScreenState();
}

class _TeacherArchiveScreenState extends ConsumerState<TeacherArchiveScreen> {
  ArchivePeriod _period = ArchivePeriod.weekly;
  bool _loading = false;
  String? _error;

  ({DateTime from, DateTime to, String label}) _rangeFor(ArchivePeriod p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (p) {
      case ArchivePeriod.weekly:
        // أسبوع يبدأ من السبت
        final daysFromSat = today.weekday == DateTime.saturday
            ? 0
            : (today.weekday % 7) + 1;
        final sat = today.subtract(Duration(days: daysFromSat));
        return (
          from: sat,
          to: sat.add(const Duration(days: 6)),
          label: 'أسبوعي',
        );
      case ArchivePeriod.monthly:
        final from = DateTime(today.year, today.month, 1);
        final to = DateTime(today.year, today.month + 1, 0);
        return (from: from, to: to, label: 'شهري');
      case ArchivePeriod.yearly:
        final from = DateTime(today.year, 1, 1);
        final to = DateTime(today.year, 12, 31);
        return (from: from, to: to, label: 'سنوي');
    }
  }

  Future<void> _refresh() async {
    final range = _rangeFor(_period);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(demoRepositoryProvider).refreshLessonArchive(
            from: range.from,
            to: range.to,
          );
    } catch (e) {
      _error = 'تعذّر تحديث الأرشيف من الخادم — يُعرض المخزّن محليًا';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  String _statusAr(AttendanceStatus s) => switch (s) {
        AttendanceStatus.present => 'حاضر',
        AttendanceStatus.absent => 'غائب',
        AttendanceStatus.late => 'متأخر',
        AttendanceStatus.unmarked => '—',
      };

  @override
  Widget build(BuildContext context) {
    final range = _rangeFor(_period);
    final repo = ref.watch(demoRepositoryProvider);
    final user = ref.watch(authControllerProvider);
    final rows = repo.lessonArchiveForRange(from: range.from, to: range.to);
    final dateFmt = DateFormat('EEEE d MMMM y', 'ar');
    final shortFmt = DateFormat('d/M/yyyy', 'ar');

    // تجميع حسب تاريخ الجلسة
    final byDate = <DateTime, List<LessonArchiveRow>>{};
    for (final r in rows) {
      final key = DateTime(
        r.sessionDate.year,
        r.sessionDate.month,
        r.sessionDate.day,
      );
      byDate.putIfAbsent(key, () => []).add(r);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('أرشيف الدروس'),
          leading: const AppBackButton(fallback: '/teacher/settings'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<ArchivePeriod>(
                segments: const [
                  ButtonSegment(
                    value: ArchivePeriod.weekly,
                    label: Text('أسبوعي'),
                  ),
                  ButtonSegment(
                    value: ArchivePeriod.monthly,
                    label: Text('شهري'),
                  ),
                  ButtonSegment(
                    value: ArchivePeriod.yearly,
                    label: Text('سنوي'),
                  ),
                ],
                selected: {_period},
                onSelectionChanged: (s) {
                  setState(() => _period = s.first);
                  _refresh();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${shortFmt.format(range.from)} — ${shortFmt.format(range.to)}',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: rows.isEmpty
                        ? null
                        : () async {
                            try {
                              await exportLessonArchiveExcel(
                                teacherName: user?.fullName ?? '',
                                mosqueName: repo.mosqueById(user?.mosqueId ?? '')
                                        ?.name ??
                                    '',
                                from: range.from,
                                to: range.to,
                                periodLabel: range.label,
                                rows: rows,
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تعذّر التصدير: $e'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Excel'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: dates.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'لا توجد دروس مسجّلة في هذه الفترة.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: dates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final date = dates[index];
                        final dayRows = byDate[date]!;
                        return GlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateFmt.format(date),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...dayRows.map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          r.studentName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _statusAr(r.status),
                                        style: TextStyle(
                                          color: AppColors.olive
                                              .withValues(alpha: 0.95),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        r.memorizationLevel?.labelAr ?? '—',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
