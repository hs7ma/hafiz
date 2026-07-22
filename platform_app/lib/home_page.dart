import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

const _olive = Color(0xFF1F4D3A);
const _oliveDark = Color(0xFF16382A);
const _ivory = Color(0xFFF7F1E6);
const _parchment = Color(0xFFEFE6D5);
const _ink = Color(0xFF1A2420);
const _danger = Color(0xFFB23A3A);

class PlatformHomePage extends StatefulWidget {
  const PlatformHomePage({super.key, required this.api});

  final PlatformApi api;

  @override
  State<PlatformHomePage> createState() => _PlatformHomePageState();
}

class _PlatformHomePageState extends State<PlatformHomePage> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _info;
  String _tab = 'pending';
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _manualOtps = const [];

  PlatformApi get _api => widget.api;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _error = null;
      _info = null;
      _busy = true;
    });
    try {
      await _api.login(_passwordCtrl.text);
      _passwordCtrl.clear();
      setState(() => _busy = false);
      await _refresh();
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await _api.logout();
    setState(() {
      _busy = false;
      _requests = const [];
      _info = null;
      _error = null;
    });
  }

  Future<void> _refresh() async {
    if (!_api.isLoggedIn) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_tab == 'otps') {
        final otps = await _api.listManualOtps();
        if (!mounted) return;
        setState(() {
          _manualOtps = otps;
          _busy = false;
        });
        return;
      }
      final list = await _api.listRequests(
        status: _tab == 'pending' ? 'pending' : null,
      );
      if (!mounted) return;
      setState(() {
        _requests = list;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        if (e.statusCode == 401) {
          _api.logout();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _approve(String id) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;

    final chosen = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('تعيين كلمة مرور المسجد'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'أدخل كلمة مرور لمسؤول الجامع (تُحفظ في قاعدة البيانات ويستطيع تغييرها لاحقاً).',
                      style: TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setLocal(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'مطلوب';
                        if (v.trim().length < 6) return '6 أحرف على الأقل';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: obscure,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v != passwordCtrl.text) return 'غير متطابقة';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(ctx, passwordCtrl.text.trim());
                  },
                  child: const Text('موافقة وحفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordCtrl.dispose();
    confirmCtrl.dispose();
    if (chosen == null || chosen.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final data = await _api.approve(id, password: chosen);
      final password = data['generated_password']?.toString() ?? chosen;
      final wa = data['whatsapp_url']?.toString();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = 'تمت الموافقة. كلمة المرور: $password';
      });
      await Clipboard.setData(ClipboardData(text: password));
      if (wa != null && wa.isNotEmpty) {
        final uri = Uri.tryParse(wa);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _reject(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الطلب؟'),
        content: const Text('لن يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.reject(id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = 'تم رفض الطلب.';
      });
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF9F4EA), _ivory, _parchment],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'إدارة منصة حافظ',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_api.isLoggedIn) ...[
              IconButton(
                tooltip: 'تحديث',
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: _busy ? null : _logout,
                child: const Text('خروج'),
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (_info != null)
              _banner(_info!, _oliveDark, const Color(0xFFE5F3EA)),
            if (_error != null) _banner(_error!, _danger, const Color(0xFFF8E8E4)),
            if (!_api.isLoggedIn) _loginCard() else ..._dashboard(),
          ],
        ),
      ),
    );
  }

  Widget _banner(String text, Color fg, Color bg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: TextStyle(color: fg, height: 1.4)),
    );
  }

  Widget _loginCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'دخول إدارة المنصة',
            style: GoogleFonts.cairo(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'مراجعة طلبات تسجيل الجوامع والموافقة أو الرفض.',
            style: TextStyle(color: _ink.withValues(alpha: 0.65), height: 1.45),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _busy ? null : _login(),
            decoration: InputDecoration(
              labelText: 'كلمة مرور المنصة',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _olive),
              onPressed: _busy ? null : _login,
              child: Text(_busy ? 'جارٍ الدخول…' : 'دخول'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _dashboard() {
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('قيد المراجعة'),
            selected: _tab == 'pending',
            selectedColor: const Color(0xFFDCE8E0),
            onSelected: (_) {
              setState(() => _tab = 'pending');
              _refresh();
            },
          ),
          ChoiceChip(
            label: const Text('كل الطلبات'),
            selected: _tab == 'all',
            selectedColor: const Color(0xFFDCE8E0),
            onSelected: (_) {
              setState(() => _tab = 'all');
              _refresh();
            },
          ),
          ChoiceChip(
            label: Text('رموز تحقق (${_manualOtps.length})'),
            selected: _tab == 'otps',
            selectedColor: const Color(0xFFDCE8E0),
            onSelected: (_) {
              setState(() => _tab = 'otps');
              _refresh();
            },
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (_tab == 'otps') ...[
        if (_busy && _manualOtps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: _olive)),
          )
        else if (_manualOtps.isEmpty)
          _card(
            child: const Text(
              'لا رموز يدوية حالياً. تظهر هنا عندما يتعذّر إرسال البريد تلقائياً.',
            ),
          )
        else
          ..._manualOtps.map(_otpCard),
      ] else if (_busy && _requests.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator(color: _olive)),
        )
      else if (_requests.isEmpty)
        _card(child: const Text('لا توجد عناصر.'))
      else
        ..._requests.map(_requestCard),
    ];
  }

  Widget _otpCard(Map<String, dynamic> o) {
    final email = o['email']?.toString() ?? '';
    final code = o['code_plain']?.toString() ?? '—';
    final exp = o['expires_at']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(email, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 6),
            Text('ينتهي: $exp', style: TextStyle(color: _ink.withValues(alpha: 0.55))),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرمز')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('نسخ الرمز'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> r) {
    final id = r['id']?.toString() ?? '';
    final status = r['status']?.toString() ?? '';
    final addr = [
      r['governorate'],
      r['district'],
      r['area'],
    ].where((e) => e != null && '$e'.trim().isNotEmpty).join(' · ');
    final counts =
        '${r['students_range'] ?? '—'} طلاب / ${r['teachers_range'] ?? '—'} مدرّسين';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r['mosque_name']?.toString() ?? '—',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              r['email']?.toString() ?? '',
              textDirection: TextDirection.ltr,
            ),
            Text(
              r['whatsapp_phone']?.toString() ?? '',
              textDirection: TextDirection.ltr,
            ),
            if (addr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(addr),
            ],
            Text(
              counts,
              style: TextStyle(color: _ink.withValues(alpha: 0.7)),
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _olive),
                      onPressed: _busy || id.isEmpty ? null : () => _approve(id),
                      child: const Text('موافقة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || id.isEmpty ? null : () => _reject(id),
                      child: const Text('رفض'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
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
      'approved' => _oliveDark,
      'rejected' => _danger,
      _ => const Color(0xFF8A6A12),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
