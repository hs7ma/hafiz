import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/whatsapp_report.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/iraq_locations.dart';
import '../../data/remote/api_client.dart';
import '../../data/sync/sync_controller.dart';

const _kLastRegistrationEmail = 'hafiz_last_registration_email';

/// تسجيل جامع جديد من داخل التطبيق: تحقق بريد ← بيانات ← انتظار موافقة.
class MosqueRegisterScreen extends ConsumerStatefulWidget {
  const MosqueRegisterScreen({super.key});

  @override
  ConsumerState<MosqueRegisterScreen> createState() =>
      _MosqueRegisterScreenState();
}

class _MosqueRegisterScreenState extends ConsumerState<MosqueRegisterScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _detailsFormKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _mosqueCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  int _step = 0; // 0 email, 1 otp, 2 details, 3 done
  bool _busy = false;
  String? _error;
  String? _info;
  String? _verifiedEmail;
  String? _registrationProof;
  String? _governorate;
  String? _district;
  String? _studentsRange;
  String? _teachersRange;
  Map<String, dynamic>? _submittedRequest;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _mosqueCtrl.dispose();
    _phoneCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  bool get _supabaseReady => SupabaseConfig.isConfigured;

  Future<void> _sendOtp() async {
    setState(() {
      _error = null;
      _info = null;
    });
    if (!_emailFormKey.currentState!.validate()) return;
    if (!_supabaseReady) {
      setState(() => _error = 'الخادم غير مضبوط — تعذّر إرسال رمز التحقق');
      return;
    }
    setState(() => _busy = true);
    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final api = ref.read(apiClientProvider);
      final data = await api.sendRegistrationEmailOtp(email);
      if (!mounted) return;
      final delivery = data['delivery']?.toString() ?? 'email';
      setState(() {
        _busy = false;
        _step = 1;
        _info = data['message']?.toString() ??
            (delivery == 'manual'
                ? 'اطلب الرمز من إدارة المنصة ثم أدخله هنا.'
                : 'أُرسل رمز التحقق إلى بريدك. أدخله خلال دقائق.');
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
    if (!_otpFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _emailCtrl.text.trim().toLowerCase();
      final api = ref.read(apiClientProvider);
      final data = await api.verifyRegistrationEmailOtp(
        email: email,
        code: _otpCtrl.text.trim(),
      );
      if (!mounted) return;
      final proof = data['registration_proof']?.toString() ?? '';
      if (proof.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'تعذّر التحقق من الرمز';
        });
        return;
      }
      setState(() {
        _busy = false;
        _verifiedEmail = email;
        _registrationProof = proof;
        _step = 2;
        _info = 'تم التحقق من البريد. أكمل بيانات المسجد.';
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

  Future<void> _submitDetails() async {
    setState(() {
      _error = null;
      _info = null;
    });
    if (!_detailsFormKey.currentState!.validate()) return;
    if (_governorate == null || _district == null) {
      setState(() => _error = 'اختر المحافظة والقضاء');
      return;
    }
    if (_studentsRange == null || _teachersRange == null) {
      setState(() => _error = 'حدد عدد الطلاب والمدرّسين');
      return;
    }

    final proof = _registrationProof;
    if (proof == null || proof.isEmpty) {
      setState(() {
        _error = 'انتهت جلسة التحقق — أعد إرسال الرمز';
        _step = 0;
      });
      return;
    }

    final localPhone = _phoneCtrl.text.trim();
    final digits = toWhatsAppDigits(localPhone, countryCode: '964');
    if (!isPlausibleWhatsAppPhone(digits)) {
      setState(() => _error = 'رقم واتساب غير صالح');
      return;
    }

    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.submitMosqueRegistration(
        registrationProof: proof,
        mosqueName: _mosqueCtrl.text.trim(),
        email: _verifiedEmail ?? _emailCtrl.text.trim().toLowerCase(),
        whatsappPhone: digits,
        governorate: _governorate!,
        district: _district!,
        area: _areaCtrl.text.trim(),
        studentsRange: _studentsRange!,
        teachersRange: _teachersRange!,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastRegistrationEmail,
        _verifiedEmail ?? _emailCtrl.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 3;
        _submittedRequest = data['request'] is Map
            ? Map<String, dynamic>.from(data['request'] as Map)
            : null;
        _info = data['message']?.toString() ??
            'تم إرسال الطلب. تابع حالته من داخل التطبيق.';
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

  @override
  Widget build(BuildContext context) {
    final districts = IraqLocations.districtsOf(_governorate);

    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const AppBackButton(fallback: '/welcome'),
          title: const Text('تسجيل جامع جديد'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            _StepHeader(step: _step),
            const SizedBox(height: 16),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _info!,
                  style: TextStyle(
                    color: AppColors.oliveDark,
                    height: 1.45,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            if (_step == 0) _buildEmailStep(),
            if (_step == 1) _buildOtpStep(),
            if (_step == 2) _buildDetailsStep(districts),
            if (_step == 3) _buildDoneStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return GlassCard(
      child: Form(
        key: _emailFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تحقق من البريد',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'سنرسل رمزاً رقمياً (6 أرقام) إلى بريدك لتأكيد هويتك قبل إكمال طلب التسجيل. أدخل الرمز في التطبيق — لا حاجة لفتح أي رابط.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            AuthTextField(
              controller: _emailCtrl,
              label: 'البريد الإلكتروني',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onEditingComplete: _busy ? null : _sendOtp,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'مطلوب';
                if (!v.contains('@')) return 'بريد غير صالح';
                return null;
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _sendOtp,
                child: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال رمز التحقق'),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => context.push('/register/status'),
              child: const Text('متابعة حالة طلب سابق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpStep() {
    return GlassCard(
      child: Form(
        key: _otpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أدخل رمز التحقق',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'أُرسل إلى ${_emailCtrl.text.trim()}',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            AuthTextField(
              controller: _otpCtrl,
              label: 'رمز التحقق (6 أرقام)',
              hint: '123456',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onEditingComplete: _busy ? null : _verifyOtp,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'مطلوب';
                if (v.trim().length != 6) return 'أدخل الرمز المكوّن من 6 أرقام';
                return null;
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _verifyOtp,
                child: Text(_busy ? 'جارٍ التحقق…' : 'تأكيد الرمز'),
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _step = 0;
                        _otpCtrl.clear();
                        _error = null;
                        _info = null;
                      }),
              child: const Text('تغيير البريد'),
            ),
            TextButton(
              onPressed: _busy ? null : _sendOtp,
              child: const Text('إعادة إرسال الرمز'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsStep(List<String> districts) {
    return GlassCard(
      child: Form(
        key: _detailsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'بيانات المسجد',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'البريد المتحقّق: ${_verifiedEmail ?? ''}',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            AuthTextField(
              controller: _mosqueCtrl,
              label: 'اسم المسجد',
              hint: 'مثال: مسجد النور',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            Text(
              'رقم واتساب',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: const InputDecoration(
                      hintText: '7XXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'مطلوب';
                      final d = toWhatsAppDigits(v, countryCode: '964');
                      if (!isPlausibleWhatsAppPhone(d)) return 'رقم غير صالح';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _governorate,
              decoration: const InputDecoration(
                labelText: 'المحافظة',
                border: OutlineInputBorder(),
              ),
              items: IraqLocations.governorates
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() {
                _governorate = v;
                _district = null;
              }),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _district,
              decoration: const InputDecoration(
                labelText: 'القضاء',
                border: OutlineInputBorder(),
              ),
              items: districts
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: _governorate == null
                  ? null
                  : (v) => setState(() => _district = v),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            AuthTextField(
              controller: _areaCtrl,
              label: 'المنطقة',
              hint: 'اكتب اسم المنطقة أو الحي',
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _studentsRange,
              decoration: const InputDecoration(
                labelText: 'عدد الطلاب',
                border: OutlineInputBorder(),
              ),
              items: studentCountRanges
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _studentsRange = v),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _teachersRange,
              decoration: const InputDecoration(
                labelText: 'عدد المدرّسين',
                border: OutlineInputBorder(),
              ),
              items: teacherCountRanges
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _teachersRange = v),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submitDetails,
                child: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال طلب التسجيل'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneStep() {
    final status = _submittedRequest?['status']?.toString() ?? 'pending';
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_outlined,
              size: 48, color: AppColors.oliveDark),
          const SizedBox(height: 12),
          Text(
            'تم إرسال طلبك',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _info ??
                'طلبك قيد المراجعة لدى إدارة حافظ. ستُبلَّغ بحالته من داخل التطبيق.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _StatusChip(status: status),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () => context.push('/register/status'),
              child: const Text('متابعة حالة الطلب'),
            ),
          ),
          TextButton(
            onPressed: () => context.go('/welcome'),
            child: const Text('العودة لشاشة الدخول'),
          ),
        ],
      ),
    );
  }
}

class MosqueRequestStatusScreen extends ConsumerStatefulWidget {
  const MosqueRequestStatusScreen({super.key});

  @override
  ConsumerState<MosqueRequestStatusScreen> createState() =>
      _MosqueRequestStatusScreenState();
}

class _MosqueRequestStatusScreenState
    extends ConsumerState<MosqueRequestStatusScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;
  Map<String, dynamic>? _request;
  String? _statusLabel;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLastRegistrationEmail);
    if (saved != null && saved.isNotEmpty && mounted) {
      _emailCtrl.text = saved;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _error = null;
      _message = null;
      _request = null;
      _statusLabel = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.registrationRequestStatus(_emailCtrl.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastRegistrationEmail,
        _emailCtrl.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      final found = data['found'] == true;
      setState(() {
        _busy = false;
        _message = data['message']?.toString();
        if (found && data['request'] is Map) {
          _request = Map<String, dynamic>.from(data['request'] as Map);
          _statusLabel = data['status_label']?.toString();
        }
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

  @override
  Widget build(BuildContext context) {
    return SoftBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const AppBackButton(fallback: '/welcome'),
          title: const Text('حالة طلب التسجيل'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'أدخل البريد المستخدم في طلب التسجيل لمعرفة حالته.',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.7),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _emailCtrl,
                      label: 'البريد الإلكتروني',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: _busy ? null : _check,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'مطلوب';
                        if (!v.contains('@')) return 'بريد غير صالح';
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
                        onPressed: _busy ? null : _check,
                        child: Text(_busy ? 'جارٍ الاستعلام…' : 'عرض الحالة'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_request != null) ...[
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusChip(
                      status: _request!['status']?.toString() ?? '',
                      label: _statusLabel,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!, style: const TextStyle(height: 1.45)),
                    ],
                    const SizedBox(height: 14),
                    _InfoRow(
                      label: 'المسجد',
                      value: _request!['mosque_name']?.toString() ?? '—',
                    ),
                    _InfoRow(
                      label: 'العنوان',
                      value: [
                        _request!['governorate'],
                        _request!['district'],
                        _request!['area'],
                      ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                    ),
                    _InfoRow(
                      label: 'الطلاب',
                      value: _request!['students_range']?.toString() ?? '—',
                    ),
                    _InfoRow(
                      label: 'المدرّسون',
                      value: _request!['teachers_range']?.toString() ?? '—',
                    ),
                    if (_request!['status'] == 'approved') ...[
                      const SizedBox(height: 12),
                      Text(
                        'استخدم شاشة «إدارة الجامع» للدخول ببيانات واتساب.',
                        style: TextStyle(
                          color: AppColors.oliveDark,
                          height: 1.4,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/welcome'),
                        child: const Text('الذهاب لتسجيل الدخول'),
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (_message != null) ...[
              const SizedBox(height: 14),
              GlassCard(child: Text(_message!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final labels = ['البريد', 'التحقق', 'البيانات', 'النتيجة'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step
                        ? AppColors.oliveDark
                        : AppColors.ink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight:
                            i == step ? FontWeight.w800 : FontWeight.w500,
                        color: i <= step
                            ? AppColors.oliveDark
                            : AppColors.ink.withValues(alpha: 0.45),
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ??
        switch (status) {
          'pending' => 'قيد المراجعة',
          'approved' => 'مقبول',
          'rejected' => 'مرفوض',
          _ => status,
        };
    final bg = switch (status) {
      'approved' => const Color(0xFFE5F3EA),
      'rejected' => const Color(0xFFF8E8E4),
      _ => const Color(0xFFFFF3D6),
    };
    final fg = switch (status) {
      'approved' => AppColors.oliveDark,
      'rejected' => AppColors.danger,
      _ => const Color(0xFF8A6A12),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(color: fg, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.55),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
