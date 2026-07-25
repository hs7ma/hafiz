import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/supabase_config.dart';
import '../local/local_store.dart';

const _hafizTokenKey = 'hafiz_actor_token';

/// عميل خلفية حافظ عبر Supabase Edge Functions فقط.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _hafizToken;

  bool get isConfigured => SupabaseConfig.isConfigured;

  /// هل يوجد رمز جلسة حافظ مخزّن (مطلوب لـ /sync/push).
  bool get hasHafizToken =>
      _hafizToken != null && _hafizToken!.trim().isNotEmpty;

  Future<void> loadPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _hafizToken = prefs.getString(_hafizTokenKey);
  }

  Future<void> setHafizToken(String? token) async {
    _hafizToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_hafizTokenKey);
    } else {
      await prefs.setString(_hafizTokenKey, token);
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = SupabaseConfig.functionsBase;
    final p = path.startsWith('/') ? path : '/$path';
    // دعم مسارات قديمة تبدأ بـ /api/
    final normalized = p.startsWith('/api/') ? p.substring(4) : p;
    final uri = Uri.parse('$base$normalized');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'apikey': SupabaseConfig.anonKey,
      // افتراضيًا anon؛ إن وُجدت جلسة حافظ تُرسل أيضًا (متوافق مع الدوال الحالية).
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
    };
    if (_hafizToken != null && _hafizToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_hafizToken!}';
      headers['x-hafiz-token'] = _hafizToken!;
    }
    return headers;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? accessToken,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!isConfigured) {
      throw StateError('لم يُضبط SUPABASE_URL / SUPABASE_ANON_KEY');
    }
    final uri = _uri(path, query);
    final headers = _headers();
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: headers).timeout(timeout);
      case 'POST':
        res = await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(timeout);
      case 'PUT':
        res = await _client
            .put(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(timeout);
      case 'PATCH':
        res = await _client
            .patch(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(timeout);
      case 'DELETE':
        res = await _client.delete(uri, headers: headers).timeout(timeout);
      default:
        throw UnsupportedError(method);
    }

    Map<String, dynamic> decoded = {};
    if (res.body.isNotEmpty) {
      final raw = jsonDecode(res.body);
      if (raw is Map<String, dynamic>) {
        decoded = raw;
      } else if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    }

    if (res.statusCode >= 400) {
      throw ApiException(
        decoded['error']?.toString() ?? 'خطأ من الخادم (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }

    final token = decoded['hafiz_token']?.toString();
    if (token != null && token.isNotEmpty) {
      await setHafizToken(token);
    }

    return decoded;
  }

  /// فحص وصول فعلي لـ Edge Function (أطول مهلة لاستيعاب cold start على بيانات الجوال).
  Future<bool> healthCheck() async {
    try {
      final res = await _client
          .get(_uri('/health'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> registerMosque({
    required String mosqueName,
    required String adminName,
    required String email,
    required String password,
  }) {
    return _json(
      'POST',
      '/api/auth/register',
      body: {
        'mosque_name': mosqueName,
        'admin_name': adminName,
        'email': email,
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> sendRegistrationSmsOtp(String phone) {
    return _json(
      'POST',
      '/api/registration/sms-otp/send',
      body: {'phone': phone.trim()},
      timeout: const Duration(seconds: 60),
    );
  }

  Future<Map<String, dynamic>> verifyRegistrationSmsOtp({
    required String phone,
    required String code,
  }) {
    return _json(
      'POST',
      '/api/registration/sms-otp/verify',
      body: {
        'phone': phone.trim(),
        'code': code.trim(),
      },
    );
  }

  /// إرسال طلب تسجيل جامع بعد التحقق من الهاتف.
  Future<Map<String, dynamic>> submitMosqueRegistration({
    String? accessToken,
    String? registrationProof,
    required String mosqueName,
    required String whatsappPhone,
    required String governorate,
    required String district,
    required String area,
    required String studentsRange,
    required String teachersRange,
  }) {
    return _json(
      'POST',
      '/api/registration-requests',
      accessToken: accessToken,
      body: {
        'mosque_name': mosqueName,
        'whatsapp_phone': whatsappPhone,
        'governorate': governorate,
        'district': district,
        'area': area,
        'students_range': studentsRange,
        'teachers_range': teachersRange,
        if (registrationProof != null && registrationProof.isNotEmpty)
          'registration_proof': registrationProof,
      },
    );
  }

  /// متابعة حالة طلب التسجيل بالهاتف.
  Future<Map<String, dynamic>> registrationRequestStatus(String phone) {
    return _json(
      'GET',
      '/api/registration-requests/status',
      query: {'phone': phone.trim()},
    );
  }

  Future<Map<String, dynamic>> loginMosqueAdmin({
    required String mosqueName,
    required String phone,
    required String password,
  }) {
    return _json(
      'POST',
      '/api/auth/login',
      body: {
        'mosque_name': mosqueName,
        'phone': phone.trim(),
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> loginTeacher({
    required String fullName,
    required String loginCode,
  }) {
    return _json(
      'POST',
      '/api/auth/teacher-login',
      body: {
        'full_name': fullName,
        'login_code': loginCode,
      },
    );
  }

  Future<Map<String, dynamic>> loginTeacherPhone({
    required String phone,
    required String password,
  }) {
    return _json(
      'POST',
      '/api/auth/teacher-login',
      body: {
        'phone': phone.trim(),
        'password': password,
      },
    );
  }

  Future<Map<String, dynamic>> sendTeacherSmsOtp({
    required String inviteToken,
    required String phone,
  }) {
    return _json(
      'POST',
      '/api/teachers/sms-otp/send',
      body: {
        'invite_token': inviteToken,
        'phone': phone.trim(),
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<Map<String, dynamic>> verifyTeacherSmsOtp({
    required String inviteToken,
    required String phone,
    required String code,
  }) {
    return _json(
      'POST',
      '/api/teachers/sms-otp/verify',
      body: {
        'invite_token': inviteToken,
        'phone': phone.trim(),
        'code': code.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> createTeacherInvite() {
    return _json('POST', '/api/teachers/invites');
  }

  Future<Map<String, dynamic>> verifyTeacherInvite(String code) {
    return _json(
      'POST',
      '/api/teachers/invites/verify',
      body: {'code': code},
    );
  }

  Future<Map<String, dynamic>> registerTeacher({
    required String inviteToken,
    required String fullName,
    required String password,
    required String whatsappPhone,
  }) {
    return _json(
      'POST',
      '/api/teachers/register',
      body: {
        'invite_token': inviteToken,
        'full_name': fullName,
        'password': password,
        'whatsapp_phone': whatsappPhone,
      },
    );
  }

  Future<Map<String, dynamic>> loginStudent({
    required String username,
    required String loginCode,
  }) {
    return _json(
      'POST',
      '/api/auth/student-login',
      body: {
        'username': username,
        'login_code': loginCode,
      },
    );
  }

  Future<Map<String, dynamic>> createStudent({
    required String mosqueId,
    required String teacherId,
    required String fullName,
    required String gradeLevel,
    required int age,
    required String parentPhone,
  }) {
    return _json(
      'POST',
      '/api/students',
      body: {
        'mosque_id': mosqueId,
        'teacher_id': teacherId,
        'full_name': fullName,
        'grade_level': gradeLevel,
        'age': age,
        'parent_phone': parentPhone,
      },
    );
  }

  Future<Map<String, dynamic>> pushOps(List<SyncOp> ops) {
    return _json(
      'POST',
      '/api/sync/push',
      body: {'ops': ops.map((e) => e.toJson()).toList()},
    );
  }

  Future<Map<String, dynamic>> pullMosque(String mosqueId) {
    return _json(
      'GET',
      '/api/sync/pull',
      query: {'mosque_id': mosqueId},
    );
  }

  Future<Map<String, dynamic>> fetchLessonArchive({
    required String from,
    required String to,
    String? teacherId,
  }) {
    final query = <String, String>{'from': from, 'to': to};
    if (teacherId != null && teacherId.isNotEmpty) {
      query['teacher_id'] = teacherId;
    }
    return _json('GET', '/api/archive/lessons', query: query);
  }

  Future<Map<String, dynamic>> changeMosqueAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _json(
      'POST',
      '/api/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<Map<String, dynamic>> listNotifications({int limit = 50}) {
    return _json(
      'GET',
      '/api/notifications',
      query: {'limit': '$limit'},
    );
  }

  Future<Map<String, dynamic>> markNotificationRead(String id) {
    return _json('POST', '/api/notifications/$id/read');
  }

  Future<Map<String, dynamic>> markAllNotificationsRead() {
    return _json('POST', '/api/notifications/read-all');
  }

  Future<Map<String, dynamic>> registerDeviceToken({
    required String fcmToken,
    required String deviceId,
    String? foregroundContext,
    String? recipientType,
    String? recipientId,
    String? mosqueId,
    String appId = 'hafiz',
  }) {
    return _json(
      'POST',
      '/api/device-tokens',
      body: {
        'fcm_token': fcmToken,
        'device_id': deviceId,
        'app_id': appId,
        if (foregroundContext != null) 'foreground_context': foregroundContext,
        if (recipientType != null) 'recipient_type': recipientType,
        if (recipientId != null) 'recipient_id': recipientId,
        if (mosqueId != null) 'mosque_id': mosqueId,
      },
    );
  }

  Future<Map<String, dynamic>> unregisterDeviceToken({
    required String deviceId,
    required String recipientType,
    required String recipientId,
    String appId = 'hafiz',
  }) {
    return _json(
      'POST',
      '/api/device-tokens/unregister',
      body: {
        'device_id': deviceId,
        'app_id': appId,
        'recipient_type': recipientType,
        'recipient_id': recipientId,
      },
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
