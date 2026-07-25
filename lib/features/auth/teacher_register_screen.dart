import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/whatsapp_report.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';

class TeacherInviteData {
  const TeacherInviteData({
    required this.inviteToken,
    required this.mosqueId,
    required this.mosqueName,
    required this.message,
  });

  final String inviteToken;
  final String mosqueId;
  final String mosqueName;
  final String message;
}

/// تسجيل مدرّس بعد التحقق من رمز الدعوة ورقم الهاتف.
class TeacherRegisterScreen extends ConsumerStatefulWidget {
  const TeacherRegisterScreen({super.key, required this.invite});

  final TeacherInviteData invite;

  @override
  ConsumerState<TeacherRegisterScreen> createState() =>
      _TeacherRegisterScreenState();
}

class _TeacherRegisterScreenState extends ConsumerState<TeacherRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  String? _error;
  String? _info;
  String? _verifiedPhone;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _inviteMessage {
    if (widget.invite.message.isNotEmpty) return widget.invite.message;
    return 'أنت بصدد التسجيل كمدرّس لصالح «${widget.invite.mosqueName}»';
  }

  Future<void> _sendOtp() async {
    setState(() {
      _error = null;
      _info = null;
    });
    final phone = toWhatsAppDigits(_phoneCtrl.text.trim(), countryCode: '964');
    if (!isPlausibleWhatsAppPhone(phone)) {
      setState(() => _error = 'رقم الهاتف غير صالح');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.sendTeacherSmsOtp(
        inviteToken: widget.invite.inviteToken,
        phone: phone,
      );
      if (!mounted) return;
      final delivery = data['delivery']?.toString() ?? 'sms';
      final manualCode = data['code']?.toString();
      setState(() {
        _busy = false;
        _otpSent = true;
        _phoneVerified = false;
        _verifiedPhone = null;
        _info = data['message']?.toString() ??
            (delivery == 'manual' && manualCode != null
                ? 'رمز التحقق: $manualCode'
                : 'أُرسل رمز التحقق إلى هاتفك');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _error = null;
      _info = null;
    });
    final phone = toWhatsAppDigits(_phoneCtrl.text.trim(), countryCode: '964');
    final code = _otpCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'أدخل رمز التحقق المكوّن من 6 أرقام');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.verifyTeacherSmsOtp(
        inviteToken: widget.invite.inviteToken,
        phone: phone,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phoneVerified = true;
        _verifiedPhone = phone;
        _info = 'تم التحقق من رقم الهاتف. أكمل التسجيل.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_phoneVerified || _verifiedPhone == null) {
      setState(() => _error = 'تحقّق من رقم الهاتف أولاً');
      return;
    }
    setState(() => _busy = true);
    try {
      final err = await ref.read(authControllerProvider.notifier).registerTeacher(
            inviteToken: widget.invite.inviteToken,
            fullName: _nameCtrl.text,
            password: _passwordCtrl.text,
            whatsappPhone: _verifiedPhone!,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      context.go('/teacher');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const AppBackButton(fallback: '/welcome'),
          title: const Text('تسجيل المدرّس'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.invite.mosqueName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.oliveDark,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _inviteMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink.withValues(alpha: 0.7),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthTextField(
                      controller: _nameCtrl,
                      label: 'الاسم الثلاثي',
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 14),
                    AuthTextField(
                      controller: _passwordCtrl,
                      label: 'كلمة المرور',
                      obscureText: _obscure,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'مطلوب';
                        if (v.length < 6) return '6 أحرف على الأقل';
                        return null;
                      },
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
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            enabled: !_phoneVerified,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
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
                              final d =
                                  toWhatsAppDigits(v, countryCode: '964');
                              if (!isPlausibleWhatsAppPhone(d)) {
                                return 'رقم غير صالح';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: (_busy || _phoneVerified) ? null : _sendOtp,
                        child: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال رمز التحقق'),
                      ),
                    ),
                    if (_otpSent && !_phoneVerified) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'رمز التحقق',
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: _busy ? null : _verifyOtp,
                          child: const Text('تحقق من الرمز'),
                        ),
                      ),
                    ],
                    if (_phoneVerified) ...[
                      const SizedBox(height: 10),
                      Text(
                        '✓ تم التحقق من رقم الهاتف',
                        style: TextStyle(color: AppColors.oliveDark),
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _info!,
                        style: TextStyle(
                          color: AppColors.oliveDark,
                          height: 1.4,
                        ),
                      ),
                    ],
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
                        onPressed: (_busy || !_phoneVerified) ? null : _submit,
                        child: Text(
                          _busy ? 'جارٍ التسجيل…' : 'إنشاء الحساب والدخول',
                        ),
                      ),
                    ),
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
