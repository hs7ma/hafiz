import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/demo_repository.dart';

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({super.key, required this.teacherId});

  final String teacherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final teachers = ref.watch(teachersControllerProvider);
    final repo = ref.watch(demoRepositoryProvider);
    final quran = ref.watch(quranRepositoryProvider);
    final homework = ref.watch(homeworkControllerProvider);

    final teacher = teachers.where((t) => t.id == teacherId).firstOrNull ??
        repo.teacherById(teacherId);

    if (teacher == null ||
        user == null ||
        teacher.mosqueId != user.mosqueId) {
      return SoftBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('بروفايل المدرّس'),
            leading: const AppBackButton(fallback: '/admin'),
          ),
          body: const Center(child: Text('المدرّس غير موجود.')),
        ),
      );
    }

    final students = repo.studentsForTeacher(teacher.id);
    final levels = repo.memorizationOverviewForTeacher(teacher.id);

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(teacher.fullName),
          leading: const AppBackButton(fallback: '/admin'),
          actions: [
            IconButton(
              tooltip: 'تعديل الاسم',
              onPressed: () => _editTeacher(context, ref, teacher),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'حذف المدرّس',
              onPressed: () => _confirmDelete(context, ref, teacher),
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            FadeSlideIn(
              child: GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.softGreen,
                      child: Text(
                        teacher.englishPrefix,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.oliveDark,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teacher.fullName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teacher.englishName,
                            style: TextStyle(
                              color: AppColors.ink.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${students.length} طالب',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.oliveDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'رمز الدخول: ${teacher.loginCode}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'نسخ الرمز',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: teacher.loginCode),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم نسخ الرمز'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'مستويات الحفظ في الحلقة',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: GlassCard(
                child: students.isEmpty
                    ? const Text('لا يوجد طلبة في حلقة هذا المدرّس بعد.')
                    : Column(
                        children: MemorizationLevel.values.map((level) {
                          final count = levels[level] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    level.labelAr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minWidth: 36),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.softGreen,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.oliveDark,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'الطلبة وتفاصيل الحفظ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            if (students.isEmpty)
              const GlassCard(
                child: Text(
                  'عندما يضيف المدرّس طلبة، ستظهر هنا مستوياتهم وواجباتهم.',
                ),
              )
            else
              ...students.asMap().entries.map((e) {
                final s = e.value;
                final level = repo.latestMemorizationFor(s.id);
                final hw = homework[s.id];
                return FadeSlideIn(
                  delay: Duration(milliseconds: 120 + e.key * 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.softGreen,
                                child: Text(
                                  s.fullName.isEmpty ? '?' : s.fullName[0],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.oliveDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${s.gradeLevel} · ${s.age} سنة',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.ink
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _detailRow(
                            'مستوى الحفظ',
                            level?.labelAr ?? 'لم يُقيَّم بعد',
                          ),
                          _detailRow(
                            'الواجب',
                            hw == null
                                ? 'لا واجب'
                                : '${quran.surahByNumber(hw.surahNumber).name} ${hw.fromAyah}–${hw.toAyah}',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.55)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TeacherAccount teacher,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المدرّس'),
        content: Text(
          'حذف «${teacher.fullName}» سيحذف طلبته أيضًا. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ref.read(teachersControllerProvider.notifier).remove(teacher.id);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/admin');
      }
    }
  }

  Future<void> _editTeacher(
    BuildContext context,
    WidgetRef ref,
    TeacherAccount teacher,
  ) async {
    final nameCtrl = TextEditingController(text: teacher.fullName);
    final englishCtrl = TextEditingController(text: teacher.englishName);
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تعديل بيانات المدرّس',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'رمز الدخول يبقى كما هو: ${teacher.loginCode}',
                  style: TextStyle(
                    color: AppColors.ink.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: nameCtrl,
                  label: 'الاسم بالعربية',
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: englishCtrl,
                  label: 'الاسم بالإنجليزية',
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'مطلوب';
                    if (!RegExp(r'[A-Za-z]').hasMatch(v)) {
                      return 'يلزم أحرف لاتينية';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      final err =
                          ref.read(teachersControllerProvider.notifier).update(
                                teacherId: teacher.id,
                                fullName: nameCtrl.text,
                                englishName: englishCtrl.text,
                              );
                      if (err != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تحديث بيانات المدرّس')),
                      );
                    },
                    child: const Text('حفظ التعديلات'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
