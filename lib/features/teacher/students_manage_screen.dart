import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/demo_repository.dart';

class StudentsManageScreen extends ConsumerWidget {
  const StudentsManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(studentsControllerProvider);

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('إدارة الطلبة'),
          leading: const AppBackButton(fallback: '/teacher'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEditor(context, ref),
          backgroundColor: AppColors.olive,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('إضافة طالب'),
        ),
        body: students.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا يوجد طلبة بعد. أضف طالبًا وسيُولَّد له اسم مستخدم ورمز دخول.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: students.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final s = students[index];
                  return GlassCard(
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
                                  color: AppColors.oliveDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'تعديل',
                              onPressed: () =>
                                  _openEditor(context, ref, student: s),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              onPressed: () =>
                                  _confirmDelete(context, ref, s),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _infoRow('المرحلة الدراسية', s.gradeLevel),
                        _infoRow('العمر', '${s.age} سنة'),
                        _infoRow('رقم ولي الأمر', s.parentPhone),
                        _infoRow('اسم المستخدم', s.loginUsername),
                        _infoRow('رمز الدخول', s.loginCode),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        '${s.loginUsername}\n${s.loginCode}',
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ بيانات الدخول'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('نسخ الدخول'),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                final code = ref
                                    .read(studentsControllerProvider.notifier)
                                    .regenerateCode(s.id);
                                if (code == null) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('رمز جديد: $code'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('إعادة توليد الرمز'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6)),
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
    StudentProfile student,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الطالب'),
        content: Text('هل تريد حذف «${student.fullName}» من الحلقة؟'),
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
    if (ok == true) {
      ref.read(studentsControllerProvider.notifier).remove(student.id);
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    StudentProfile? student,
  }) async {
    final nameCtrl = TextEditingController(text: student?.fullName ?? '');
    final gradeCtrl = TextEditingController(text: student?.gradeLevel ?? '');
    final ageCtrl =
        TextEditingController(text: student == null ? '' : '${student.age}');
    final phoneCtrl = TextEditingController(text: student?.parentPhone ?? '');
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    student == null ? 'إضافة طالب' : 'تعديل بيانات الطالب',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (student == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'سيُولَّد اسم مستخدم ورمز دخول تلقائيًا بعد الحفظ.',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: nameCtrl,
                    label: 'الاسم',
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: gradeCtrl,
                    label: 'المرحلة الدراسية',
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: ageCtrl,
                    label: 'العمر',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 4 || n > 25) {
                        return 'أدخل عمرًا بين 4 و 25';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: phoneCtrl,
                    label: 'رقم ولي الأمر',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'رقم غير صالح'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final age = int.parse(ageCtrl.text);
                        if (student == null) {
                          final result = await ref
                              .read(studentsControllerProvider.notifier)
                              .add(
                                fullName: nameCtrl.text,
                                gradeLevel: gradeCtrl.text,
                                age: age,
                                parentPhone: phoneCtrl.text,
                              );
                          if (!context.mounted) return;
                          if (result.error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.error!)),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          _showCredentials(context, result.student!);
                        } else {
                          ref.read(studentsControllerProvider.notifier).update(
                                student.copyWith(
                                  fullName: nameCtrl.text.trim(),
                                  gradeLevel: gradeCtrl.text.trim(),
                                  age: age,
                                  parentPhone: phoneCtrl.text.trim(),
                                ),
                              );
                          Navigator.pop(context);
                        }
                      },
                      child: Text(student == null ? 'حفظ وتوليد الدخول' : 'تحديث'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCredentials(
    BuildContext context,
    StudentProfile student,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بيانات دخول الطالب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('شارك هذه البيانات مع الطالب أو ولي الأمر.'),
            const SizedBox(height: 12),
            Text(
              'اسم المستخدم: ${student.loginUsername}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'الرمز: ${student.loginCode}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: '${student.loginUsername}\n${student.loginCode}',
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }
}
