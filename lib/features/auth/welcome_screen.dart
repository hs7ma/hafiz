import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/constants/supabase_config.dart';
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
                  subtitle: 'الدخول بعد موافقة حافظ — اسم المسجد والبريد وكلمة المرور',
                  icon: Icons.account_balance_outlined,
                  onTap: () => setState(() => _role = _AuthRole.admin),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  title: 'المدرّس',
                  subtitle: 'رمز دعوة من إدارة المسجد، أو بريد وكلمة مرور بعد التسجيل',
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
                  label: const Text('تسجيل جامع جديد'),
                ),
                TextButton(
                  onPressed: () => context.push('/register/status'),
                  child: const Text('متابعة حالة طلب التسجيل'),
                ),
                const SizedBox(height: 12),
                Text(
                  'تجريبي: مسجد النور · admin@demo.local / demo1234\n'
                  'مدرّس: بعد دعوة من المشرف → تسجيل بالبريد\n'
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
    final repoPending = ref.watch(demoRepositoryProvider).pendingSyncCount;
    final configured = SupabaseConfig.isConfigured;
    final sync = configured ? ref.watch(syncControllerProvider) : null;
    final pending = sync?.pending ?? repoPending;

    late final String text;
    late final Color bg;
    late final IconData icon;

    if (!configured) {
      text = 'وضع محلي أوفلاين — تُحفظ البيانات على الجهاز';
      bg = AppColors.softGreen.withValues(alpha: 0.55);
      icon = Icons.phone_android;
    } else if (sync!.phase == SyncPhase.syncing) {
      text = sync.message;
      bg = AppColors.softGreen.withValues(alpha: 0.55);
      icon = Icons.cloud_sync_outlined;
    } else if (sync.needsLogin ||
        (sync.phase == SyncPhase.error && sync.message.contains('تسجيل الدخول'))) {
      text = sync.message.isNotEmpty
          ? '${sync.message}\nاضغط بعد تسجيل الدخول للمزامنة'
          : 'يلزم تسجيل الدخول لمزامنة $pending عملية — اضغط بعد الدخول';
      bg = const Color(0xFFFFE0B2).withValues(alpha: 0.9);
      icon = Icons.lock_outline;
    } else if (sync.phase == SyncPhase.error) {
      text = sync.message.isNotEmpty
          ? '${sync.message}\nاضغط لإعادة المحاولة'
          : 'تعذّرت المزامنة — اضغط لإعادة المحاولة';
      bg = const Color(0xFFFFE0B2).withValues(alpha: 0.9);
      icon = Icons.error_outline;
    } else if (sync.phase == SyncPhase.offline) {
      text = sync.message.isNotEmpty
          ? sync.message
          : (pending > 0
              ? 'بدون اتصال — $pending عملية محفوظة محليًا'
              : 'بدون إنترنت — التغييرات محفوظة محليًا');
      bg = const Color(0xFFFFE0B2).withValues(alpha: 0.9);
      icon = Icons.cloud_off_outlined;
    } else if (pending > 0) {
      text = sync.message.isNotEmpty && !sync.message.contains('لا طابور')
          ? '${sync.message}\nاضغط لإعادة المحاولة'
          : 'بانتظار المزامنة: $pending عملية — اضغط للإرسال الآن';
      bg = const Color(0xFFFFE0B2).withValues(alpha: 0.9);
      icon = Icons.cloud_upload_outlined;
    } else {
      text = sync.message.isNotEmpty && sync.message != 'لا طابور معلّق'
          ? sync.message
          : 'متصل بـ Supabase — المزامنة جاهزة';
      bg = AppColors.softGreen.withValues(alpha: 0.55);
      icon = Icons.cloud_done_outlined;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: configured
            ? () => ref
                .read(syncControllerProvider.notifier)
                .flush(reason: 'manual', force: true)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.oliveDark),
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
              if (configured)
                Icon(
                  Icons.refresh,
                  size: 18,
                  color: AppColors.oliveDark.withValues(alpha: 0.7),
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _mosqueCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final err = await ref.read(authControllerProvider.notifier).loginMosqueAdmin(
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
                'دخول إدارة الجامع',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'أدخل اسم المسجد والبريد وكلمة المرور التي استلمتها بعد موافقة حافظ.',
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
                autofillHints: const [AutofillHints.password],
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _modeLogin = false;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
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
        await ref.read(authControllerProvider.notifier).loginTeacherEmail(
              email: _emailCtrl.text,
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
                ? 'استخدم البريد وكلمة المرور بعد إكمال التسجيل.'
                : 'أدخل رمز الدعوة الذي أرسلته إدارة المسجد (صالح لدقيقتين).',
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
                  AuthTextField(
                    controller: _emailCtrl,
                    label: 'البريد الإلكتروني',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
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
