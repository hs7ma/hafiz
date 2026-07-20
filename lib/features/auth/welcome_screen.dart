import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/constants/api_config.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SoftBackground(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: const HafizLogo(height: 96),
            ),
            const SizedBox(height: 20),
            Text(
              'حافظ',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.oliveDark,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'حضورٌ منظم… وحفظٌ متتابع',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AuthRole { admin, teacher, student }

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  _AuthRole? _role;

  @override
  Widget build(BuildContext context) {
    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              const FadeSlideIn(child: HafizLogo(height: 72)),
              const SizedBox(height: 16),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'حافظ',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.oliveDark,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  'إدارة حلقات التحفيظ في المسجد',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: AppColors.ink.withValues(alpha: 0.75),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              const _SyncStatusBanner(),
              const SizedBox(height: 16),
              if (_role == null) ...[
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: Text(
                    'اختر طريقة الدخول',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                _RoleTile(
                  title: 'إدارة الجامع',
                  subtitle: 'تسجيل المسجد ومتابعة المستويات والمدرّسين',
                  icon: Icons.account_balance_outlined,
                  onTap: () => setState(() => _role = _AuthRole.admin),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  title: 'المدرّس',
                  subtitle: 'الاسم والرمز من إدارة المسجد',
                  icon: Icons.school_outlined,
                  onTap: () => setState(() => _role = _AuthRole.teacher),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  title: 'الطالب',
                  subtitle: 'اسم المستخدم والرمز من المدرّس',
                  icon: Icons.menu_book_outlined,
                  onTap: () => setState(() => _role = _AuthRole.student),
                ),
                const SizedBox(height: 20),
                Text(
                  'تجريبي: مسجد النور · admin@demo.local / demo1234\n'
                  'مدرّس: الشيخ إبراهيم / IB482917\n'
                  'طالب: ahmad_yusuf / A7K3M',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.ink.withValues(alpha: 0.5),
                        height: 1.5,
                      ),
                ),
              ] else ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _role = null),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('تغيير الدور'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_role == _AuthRole.admin) const _AdminAuthForm(),
                if (_role == _AuthRole.teacher) const _TeacherAuthForm(),
                if (_role == _AuthRole.student) const _StudentAuthForm(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncStatusBanner extends ConsumerWidget {
  const _SyncStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(demoRepositoryProvider).pendingSyncCount;
    final configured = ApiConfig.isConfigured;
    final sync = configured ? ref.watch(syncControllerProvider) : null;

    final text = !configured
        ? 'وضع محلي أوفلاين — لا خادم مضبوط (API_BASE_URL)'
        : sync!.phase == SyncPhase.syncing
            ? sync.message
            : pending > 0
                ? 'بانتظار المزامنة: $pending عملية'
                : 'متصل بالخادم — المزامنة جاهزة';

    return Material(
      color: AppColors.softGreen.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: configured
            ? () => ref.read(syncControllerProvider.notifier).flush()
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                configured ? Icons.cloud_sync_outlined : Icons.phone_android,
                size: 20,
                color: AppColors.oliveDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.oliveDark,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.oliveDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          const Icon(Icons.chevron_left),
        ],
      ),
    );
  }
}

class _AdminAuthForm extends ConsumerStatefulWidget {
  const _AdminAuthForm();

  @override
  ConsumerState<_AdminAuthForm> createState() => _AdminAuthFormState();
}

class _AdminAuthFormState extends ConsumerState<_AdminAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _mosqueCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _mosqueCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = ref.read(authControllerProvider.notifier);
    final err = _register
        ? auth.registerMosque(
            mosqueName: _mosqueCtrl.text,
            adminName: _nameCtrl.text,
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          )
        : auth.loginMosqueAdmin(
            mosqueName: _mosqueCtrl.text,
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    context.go('/admin');
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _register ? 'إنشاء مسجد جديد' : 'دخول إدارة الجامع',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _register
                    ? 'أنشئ حسابًا باسم المسجد والبريد وكلمة المرور.'
                    : 'أدخل اسم المسجد والبريد وكلمة المرور.',
                style: TextStyle(
                  color: AppColors.ink.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 18),
              AuthTextField(
                controller: _mosqueCtrl,
                label: 'اسم المسجد',
                hint: 'مثال: مسجد النور',
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.organizationName],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              if (_register) ...[
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _nameCtrl,
                  label: 'اسم المسؤول',
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
              ],
              const SizedBox(height: 14),
              AuthTextField(
                controller: _emailCtrl,
                label: 'البريد الإلكتروني',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'مطلوب';
                  if (!v.contains('@')) return 'بريد غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passwordCtrl,
                label: 'كلمة المرور',
                obscureText: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                textInputAction: TextInputAction.done,
                autofillHints: [
                  _register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onEditingComplete: _submitting ? null : _submit,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'مطلوب';
                  if (v.length < 6) return '6 أحرف على الأقل';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _register ? 'إنشاء مسجد' : 'دخول الإدارة',
                  ),
                ),
              ),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(
                  _register
                      ? 'لديك حساب؟ سجّل الدخول'
                      : 'مسجد جديد؟ أنشئ حساب إدارة',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherAuthForm extends ConsumerStatefulWidget {
  const _TeacherAuthForm();

  @override
  ConsumerState<_TeacherAuthForm> createState() => _TeacherAuthFormState();
}

class _TeacherAuthFormState extends ConsumerState<_TeacherAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final err = ref.read(authControllerProvider.notifier).loginTeacher(
          fullName: _nameCtrl.text,
          code: _codeCtrl.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    context.go('/teacher');
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'دخول المدرّس',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'استخدم الاسم والرمز اللذين وفّرتهما إدارة المسجد.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            AuthTextField(
              controller: _nameCtrl,
              label: 'اسم المدرّس',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _codeCtrl,
              label: 'رمز الدخول',
              hint: 'مثال: IB482917',
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              onEditingComplete: _submitting ? null : _submit,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'مطلوب';
                if (v.trim().length < 8) return 'الرمز غير مكتمل';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: const Text('دخول المدرّس'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentAuthForm extends ConsumerStatefulWidget {
  const _StudentAuthForm();

  @override
  ConsumerState<_StudentAuthForm> createState() => _StudentAuthFormState();
}

class _StudentAuthFormState extends ConsumerState<_StudentAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final err = ref.read(authControllerProvider.notifier).loginStudent(
          username: _userCtrl.text,
          code: _codeCtrl.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    context.go('/student');
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'دخول الطالب',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'اسم المستخدم والرمز من المدرّس.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            AuthTextField(
              controller: _userCtrl,
              label: 'اسم المستخدم',
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _codeCtrl,
              label: 'رمز الدخول',
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.characters,
              onEditingComplete: _submitting ? null : _submit,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'مطلوب';
                final len = v.trim().length;
                if (len < 5 || len > 8) return 'الرمز بين 5 و 8 رموز';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: const Text('دخول الطالب'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
