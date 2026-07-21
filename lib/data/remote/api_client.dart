import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_config.dart';
import '../../core/constants/supabase_config.dart';
import '../local/local_store.dart';

const _hafizTokenKey = 'hafiz_actor_token';

/// عميل الخلفية: يفضّل Edge Functions على Supabase، مع احتياطي Railway.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _hafizToken;

  bool get isConfigured =>
      SupabaseConfig.isConfigured || ApiConfig.isConfigured;

  bool get usesSupabase => SupabaseConfig.isConfigured;

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
    if (usesSupabase) {
      final base = SupabaseConfig.functionsBase;
      final p = path.startsWith('/') ? path : '/$path';
      // Strip legacy /api prefix when calling Edge Function
      final normalized = p.startsWith('/api/') ? p.substring(4) : p;
      return Uri.parse('$base$normalized').replace(queryParameters: query);
    }
    final base = ApiConfig.normalizedBase;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (usesSupabase) {
      headers['apikey'] = SupabaseConfig.anonKey;
      final bearer = (_hafizToken != null && _hafizToken!.isNotEmpty)
          ? _hafizToken!
          : SupabaseConfig.anonKey;
      headers['Authorization'] = 'Bearer $bearer';
      if (_hafizToken != null && _hafizToken!.isNotEmpty) {
        headers['x-hafiz-token'] = _hafizToken!;
      }
    }
    return headers;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!isConfigured) {
      throw StateError('لم يُضبط SUPABASE_URL/ANON_KEY ولا API_BASE_URL');
    }
    final uri = _uri(path, query);
    final headers = _headers();
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: headers).timeout(
              const Duration(seconds: 20),
            );
      case 'POST':
        res = await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      case 'PUT':
        res = await _client
            .put(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      case 'PATCH':
        res = await _client
            .patch(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      case 'DELETE':
        res = await _client.delete(uri, headers: headers).timeout(
              const Duration(seconds: 20),
            );
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

  Future<bool> healthCheck() async {
    try {
      final res = await _client
          .get(_uri(usesSupabase ? '/health' : '/health'), headers: _headers())
          .timeout(const Duration(seconds: 4));
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

  Future<Map<String, dynamic>> loginMosqueAdmin({
    required String mosqueName,
    required String email,
    required String password,
  }) {
    return _json(
      'POST',
      '/api/auth/login',
      body: {
        'mosque_name': mosqueName,
        'email': email,
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
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
