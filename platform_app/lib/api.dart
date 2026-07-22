import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_config.dart';

class PlatformApi {
  PlatformApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  String? get token => _token;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${SupabaseConfig.apiBase}$p').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool withPlatform = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'apikey': SupabaseConfig.anonKey,
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
    };
    if (withPlatform && _token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
      headers['x-platform-token'] = _token!;
    }
    return headers;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = false,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw ApiException('لم يُضبط SUPABASE_URL / SUPABASE_ANON_KEY');
    }
    final uri = _uri(path, query);
    final headers = _headers(withPlatform: auth);
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
    return decoded;
  }

  Future<void> login(String password) async {
    final data = await _json(
      'POST',
      '/platform/login',
      body: {'password': password},
    );
    final t = data['token']?.toString();
    if (t == null || t.isEmpty) {
      throw ApiException('لم يُرجع الخادم رمز جلسة');
    }
    _token = t;
  }

  Future<void> logout() async {
    final t = _token;
    if (t == null) return;
    try {
      await _json('POST', '/platform/logout', auth: true);
    } catch (_) {
      /* ignore */
    }
    _token = null;
  }

  Future<List<Map<String, dynamic>>> listRequests({String? status}) async {
    final data = await _json(
      'GET',
      '/registration-requests',
      auth: true,
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    final raw = data['requests'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
    }
    return list;
  }

  Future<Map<String, dynamic>> approve(String id, {String? password}) {
    return _json(
      'POST',
      '/registration-requests/$id/approve',
      auth: true,
      body: {
        if (password != null && password.trim().isNotEmpty)
          'password': password.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> reject(String id) {
    return _json('POST', '/registration-requests/$id/reject', auth: true);
  }

  Future<List<Map<String, dynamic>>> listManualOtps() async {
    final data = await _json('GET', '/platform/manual-otps', auth: true);
    final raw = data['otps'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
    }
    return list;
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
