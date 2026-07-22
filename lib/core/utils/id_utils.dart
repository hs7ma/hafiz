import 'package:uuid/uuid.dart';

final _uuid = const Uuid();

final _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

bool isUuid(String? value) {
  final s = value?.trim() ?? '';
  return s.isNotEmpty && _uuidRe.hasMatch(s);
}

/// Converts legacy/demo ids like `stu-1` into stable UUIDs for Postgres.
String ensureUuid(String? value) {
  final s = value?.trim() ?? '';
  if (s.isEmpty) return _uuid.v4();
  if (_uuidRe.hasMatch(s)) return s;
  return _uuid.v5(Namespace.url.value, 'hafiz-id:$s');
}

const _uuidKeys = {
  'id',
  'mosque_id',
  'teacher_id',
  'student_id',
  'session_id',
  'admin_id',
  'actor_id',
};

Map<String, dynamic> sanitizeSyncPayload(Map<String, dynamic> payload) {
  final out = Map<String, dynamic>.from(payload);
  for (final key in _uuidKeys) {
    if (out.containsKey(key) && out[key] != null) {
      final raw = out[key].toString();
      if (raw.trim().isNotEmpty) out[key] = ensureUuid(raw);
    }
  }
  return out;
}
