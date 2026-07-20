import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/demo_repository.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final teachers = ref.watch(teachersControllerProvider);
    final students = ref.watch(studentsControllerProvider);
    final repo = ref.watch(demoRepositoryProvider);
    final mosque = user == null ? null : repo.mosqueById(user.mosqueId);

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('إدارة الجامع'),
          actions: [
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
                      mosque?.name ?? 'المسجد',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.oliveDark,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text('مرحبًا، ${user?.fullName ?? ''}'),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 60),
              child: Row(
                children: [
                  Expanded(
                    child: _countTile(
                      context,
                      label: 'المدرّسون',
                      value: '${teachers.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _countTile(
                      context,
                      label: 'الطلبة',
                      value: '${students.length}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المدرّسون',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _addTeacher(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('إضافة'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'افتح بروفايل كل مدرّس لعرض طلبته وتفاصيل الحفظ.',
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 10),
            if (teachers.isEmpty)
              const GlassCard(
                child: Text(
                  'أضف مدرّسًا ليبدأ إدارة حلقته. سيُعرض الرمز مرة واحدة بعد الإنشاء.',
                ),
              )
            else
              ...teachers.asMap().entries.map((e) {
                final t = e.value;
                final count = repo.studentsForTeacher(t.id).length;
                return FadeSlideIn(
                  delay: Duration(milliseconds: 100 + e.key * 40),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      onTap: () => context.push('/admin/teachers/${t.id}'),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.softGreen,
                            child: Text(
                              t.englishPrefix,
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
                                  t.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  count == 0
                                      ? 'لا طلبة بعد'
                                      : '$count طالب',
                                  style: TextStyle(
                                    color: AppColors.ink.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_left),
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

  Widget _countTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.oliveDark,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTeacher(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final englishCtrl = TextEditingController();
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
                  'إضافة مدرّس',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
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
                  label: 'الاسم بالإنجليزية (لحرفي الرمز)',
                  hint: 'مثال: Ibrahim',
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
                      final result =
                          ref.read(teachersControllerProvider.notifier).add(
                                fullName: nameCtrl.text,
                                englishName: englishCtrl.text,
                              );
                      if (result.error != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.error!)),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      _showCredentials(
                        context,
                        title: 'تم إنشاء حساب المدرّس',
                        lines: [
                          'الاسم: ${result.teacher!.fullName}',
                          'الرمز: ${result.teacher!.loginCode}',
                        ],
                        copyText: result.teacher!.loginCode,
                      );
                    },
                    child: const Text('إنشاء وتوليد الرمز'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCredentials(
    BuildContext context, {
    required String title,
    required List<String> lines,
    required String copyText,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('احفظ هذه البيانات الآن وشاركها مع المدرّس.'),
            const SizedBox(height: 12),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  l,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyText));
              Navigator.pop(context);
            },
            child: const Text('نسخ الرمز'),
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
