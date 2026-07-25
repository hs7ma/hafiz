import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_widgets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/data_provenance_widgets.dart';
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
    final pendingSync = repo.pendingSyncCount;

    final emptyTeacherRings = teachers
        .where((t) => repo.studentsForTeacher(t.id).isEmpty)
        .length;

    final teacherLabel = teachers.isEmpty
        ? 'لا مدرّسين بعد'
        : arabicCount(
            teachers.length,
            one: 'مدرّس واحد',
            two: 'مدرّسان',
            many: 'مدرّسين',
          );
    final studentLabel = students.isEmpty
        ? 'لا طلاب بعد'
        : arabicCount(
            students.length,
            one: 'طالب واحد',
            two: 'طالبان',
            many: 'طالبًا',
          );
    final ringLabel = teachers.isEmpty
        ? 'لا حلقات بعد'
        : arabicCount(
            teachers.length,
            one: 'حلقة واحدة',
            two: 'حلقتان',
            many: 'حلقة',
          );

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('إدارة المسجد'),
          actions: [
            const NotificationBellAction(),
            IconButton(
              tooltip: 'تغيير كلمة المرور',
              onPressed: () => _changePassword(context, ref),
              icon: const Icon(Icons.lock_outline_rounded),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
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
            const SyncWarningBanner(),
            const SizedBox(height: 12),
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
                  ],
                ),
              ),
            ),
            if (pendingSync > 0) ...[
              const SizedBox(height: 12),
              FadeSlideIn(
                child: DashboardAttentionBanner(
                  icon: Icons.cloud_upload_outlined,
                  message: pendingSync == 1
                      ? 'توجد بيانات بانتظار المزامنة. تأكد من اتصال الإنترنت ثم انتظر قليلًا.'
                      : 'توجد $pendingSync بيانات بانتظار المزامنة. تأكد من اتصال الإنترنت ثم انتظر قليلًا.',
                ),
              ),
            ],
            if (emptyTeacherRings > 0) ...[
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 30),
                child: DashboardAttentionBanner(
                  icon: Icons.groups_outlined,
                  message: emptyTeacherRings == 1
                      ? 'حلقة واحدة بلا طلاب — اطلب من المدرّس إضافة طلاب أو راجع الحلقة.'
                      : '$emptyTeacherRings حلقات بلا طلاب — اطلب من المدرّسين إضافة طلاب أو راجع الحلقات.',
                ),
              ),
            ],
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 40),
              child: Text(
                'ملخص المسجد',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delay: const Duration(milliseconds: 50),
              child: Row(
                children: [
                  Expanded(
                    child: DashboardStatTile(
                      label: 'المدرّسون',
                      value: teacherLabel,
                      hint: teachers.isEmpty
                          ? 'ادعُ مدرّسًا لبدء الحلقات'
                          : 'يديرون حلقات التحفيظ',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashboardStatTile(
                      label: 'الطلاب',
                      value: studentLabel,
                      hint: students.isEmpty
                          ? 'يُضافون من لوحة المدرّس'
                          : 'مسجّلون في حلقات المسجد',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FadeSlideIn(
              delay: const Duration(milliseconds: 55),
              child: DashboardStatTile(
                label: 'الحلقات',
                value: ringLabel,
                hint: emptyTeacherRings == 0
                    ? 'جميع الحلقات فيها طلاب'
                    : '$emptyTeacherRings ${emptyTeacherRings == 1 ? 'حلقة تحتاج' : 'حلقات تحتاج'} إضافة طلاب',
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
                  onPressed: () => _inviteTeacher(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('دعوة مدرّس'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'اضغط على مدرّس لعرض حلقته.',
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'أنشئ رمز دعوة صالحاً لـ3 ساعات وشاركه مع المدرّس ليسجّل حسابه.',
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
                                      : '$count طالب في حلقته',
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

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تغيير كلمة المرور',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اختر كلمة مرور جديدة (8 أحرف على الأقل وتتضمن حرفاً ورقماً).',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AuthTextField(
                      controller: currentCtrl,
                      label: 'كلمة المرور الحالية',
                      obscureText: obscure,
                      onToggleObscure: () =>
                          setLocal(() => obscure = !obscure),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: newCtrl,
                      label: 'كلمة المرور الجديدة',
                      obscureText: obscure,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'مطلوب';
                        if (v.length < 8) return '8 أحرف على الأقل';
                        if (!RegExp(r'[A-Za-z]').hasMatch(v)) {
                          return 'يجب أن تتضمن حرفاً';
                        }
                        if (!RegExp(r'\d').hasMatch(v)) {
                          return 'يجب أن تتضمن رقماً';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      controller: confirmCtrl,
                      label: 'تأكيد كلمة المرور',
                      obscureText: obscure,
                      validator: (v) {
                        if (v != newCtrl.text) return 'غير متطابقة';
                        return null;
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        final err = await ref
                            .read(authControllerProvider.notifier)
                            .changeMosqueAdminPassword(
                              currentPassword: currentCtrl.text,
                              newPassword: newCtrl.text,
                            );
                        if (!ctx.mounted) return;
                        if (err != null) {
                          setLocal(() => error = err);
                          return;
                        }
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تغيير كلمة المرور بنجاح'),
                          ),
                        );
                      },
                      child: const Text('حفظ'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _inviteTeacher(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    final result =
        await ref.read(teachersControllerProvider.notifier).createInvite();
    if (!context.mounted) return;
    Navigator.pop(context); // loading

    if (result.error != null || result.invite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'تعذّر إنشاء الدعوة')),
      );
      return;
    }

    final invite = result.invite!;
    final code = invite['code']?.toString() ?? '';
    final expiresAt =
        DateTime.tryParse(invite['expires_at']?.toString() ?? '') ??
            DateTime.now().add(const Duration(hours: 3));

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _InviteCodeDialog(code: code, expiresAt: expiresAt);
      },
    );
  }
}

class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog({
    required this.code,
    required this.expiresAt,
  });

  final String code;
  final DateTime expiresAt;

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    final left = widget.expiresAt.difference(DateTime.now());
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (_left > Duration.zero) {
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (mounted) _tick();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hh = _left.inHours.toString().padLeft(2, '0');
    final mm = _left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = _left.inSeconds.remainder(60).toString().padLeft(2, '0');
    final expired = _left == Duration.zero;

    return AlertDialog(
      title: const Text('رمز دعوة المدرّس'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            expired
                ? 'انتهت صلاحية الرمز. أنشئ دعوة جديدة.'
                : 'شارك الرمز مع المدرّس فوراً. صالح لمدة:',
          ),
          const SizedBox(height: 8),
          Text(
            '$hh:$mm:$ss',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: expired ? AppColors.danger : AppColors.oliveDark,
                ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            widget.code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'رمز لمرة واحدة — صالح لمدة 3 ساعات.',
            style: TextStyle(height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: expired
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرمز')),
                  );
                },
          child: const Text('نسخ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
