import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/notifications/notification_widgets.dart';
import '../../core/utils/whatsapp_report.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';
import 'teacher_register_screen.dart';

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
              child: const HafizLogo(height: 180),
            ),
            const SizedBox(height: 12),
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
              const FadeSlideIn(
                child: Center(child: HafizLogo(height: 170)),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 100),
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
              const SyncWarningBanner(),
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
                  title: 'إدارة المسجد',
                  subtitle: 'الدخول بعد موافقة حافظ — اسم المسجد والهاتف وكلمة المرور',
                  icon: Icons.account_balance_outlined,
                  onTap: () => setState(() => _role = _AuthRole.admin),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  title: 'المدرّس',
                  subtitle: 'رمز دعوة من إدارة المسجد، أو الهاتف وكلمة المرور بعد التسجيل',
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push('/register'),
                  icon: const Icon(Icons.app_registration_outlined),
                  label: const Text('تسجيل مسجد جديد'),
                ),
                TextButton(
                  onPressed: () => context.push('/register/status'),
                  child: const Text('متابعة حالة طلب التسجيل'),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.softGreen.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.olive.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'وضع تجريبي — للاختبار فقط',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.oliveDark,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'مسجد النور · هاتف المسؤول / demo1234\n'
                        'مدرّس: بعد دعوة من المشرف → تسجيل بالهاتف\n'
                        'طالب: ahmad_yusuf / A7K3M',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.ink.withValues(alpha: 0.5),
                              height: 1.5,
                            ),
                      ),
                    ],
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
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _mosqueCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final err = await ref.read(authControllerProvider.notifier).loginMosqueAdmin(
          mosqueName: _mosqueCtrl.text,
          phone: _phoneCtrl.text,
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
                'دخول إدارة المسجد',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'أدخل اسم المسجد ورقم الهاتف ورمز الدخول من صفحة «حالة طلب التسجيل» بعد الموافقة.',
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
              const SizedBox(height: 14),
              Text(
                'رقم الهاتف',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softGreen.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      '+964',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        hintText: '7768944556 أو 07768944556',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'مطلوب';
                        final d = toWhatsAppDigits(v, countryCode: '964');
                        if (!isPlausibleWhatsAppPhone(d)) {
                          return 'رقم غير صالح';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passwordCtrl,
                label: 'رمز الدخول',
                hint: 'مثال: ABCD-EFGH',
                obscureText: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onEditingComplete: _submitting ? null : _submit,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'مطلوب';
                  final normalized =
                      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                  if (normalized.length < 8) return '8 رموز على الأقل';
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
                  child: const Text('دخول الإدارة'),
                ),
              ),
              TextButton(
                onPressed: _submitting ? null : () => context.push('/register'),
                child: const Text('مسجد جديد؟ سجّل من داخل التطبيق'),
              ),
              TextButton(
                onPressed:
                    _submitting ? null : () => context.push('/register/status'),
                child: const Text('متابعة حالة طلب التسجيل'),
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
  final _inviteFormKey = GlobalKey<FormState>();
  final _loginFormKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _modeLogin = false;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyInvite() async {
    setState(() => _error = null);
    if (!_inviteFormKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.verifyTeacherInvite(_codeCtrl.text);
      final mosque = data['mosque'];
      final token = data['invite_token']?.toString() ?? '';
      if (token.isEmpty || mosque is! Map) {
        setState(() {
          _submitting = false;
          _error = 'استجابة غير صالحة من الخادم';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      context.push(
        '/teacher/register',
        extra: TeacherInviteData(
          inviteToken: token,
          mosqueId: mosque['id']?.toString() ?? '',
          mosqueName: mosque['name']?.toString() ?? '',
          message: data['message']?.toString() ?? '',
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _login() async {
    setState(() => _error = null);
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final err =
        await ref.read(authControllerProvider.notifier).loginTeacherPhone(
              phone: _phoneCtrl.text,
              password: _passwordCtrl.text,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _modeLogin ? 'دخول المدرّس' : 'دعوة مدرّس جديد',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            _modeLogin
                ? 'استخدم رقم الهاتف وكلمة المرور بعد إكمال التسجيل.'
                : 'أدخل رمز الدعوة الذي أرسلته إدارة المسجد (صالح لـ3 ساعات).',
            style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 18),
          if (!_modeLogin)
            Form(
              key: _inviteFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthTextField(
                    controller: _codeCtrl,
                    label: 'رمز الدعوة',
                    hint: 'XXXX-XXXX-XXXX',
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.characters,
                    onEditingComplete: _submitting ? null : _verifyInvite,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      final n = v.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
                      if (n.length != 12) return 'الرمز 12 خانة';
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
                      onPressed: _submitting ? null : _verifyInvite,
                      child: Text(_submitting ? 'جارٍ التحقق…' : 'متابعة التسجيل'),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _modeLogin = true;
                              _error = null;
                            }),
                    child: const Text('لدي حساب؟ تسجيل الدخول'),
                  ),
                ],
              ),
            )
          else
            Form(
              key: _loginFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'رقم الهاتف',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softGreen.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          '+964',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: const InputDecoration(
                            hintText: '7768944556 أو 07768944556',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'مطلوب';
                            final d = toWhatsAppDigits(v, countryCode: '964');
                            if (!isPlausibleWhatsAppPhone(d)) {
                              return 'رقم غير صالح';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AuthTextField(
                    controller: _passwordCtrl,
                    label: 'كلمة المرور',
                    obscureText: _obscure,
                    onToggleObscure: () =>
                        setState(() => _obscure = !_obscure),
                    textInputAction: TextInputAction.done,
                    onEditingComplete: _submitting ? null : _login,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'مطلوب' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ? null : _login,
                      child: Text(_submitting ? 'جارٍ الدخول…' : 'دخول المدرّس'),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _modeLogin = false;
                              _error = null;
                            }),
                    child: const Text('لدي رمز دعوة'),
                  ),
                ],
              ),
            ),
        ],
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
    final err = await ref.read(authControllerProvider.notifier).loginStudent(
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
