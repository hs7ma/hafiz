import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const _kSnapshot = 'hafiz_local_snapshot_v1';
const _kSyncQueue = 'hafiz_sync_queue_v1';
const _kSessionUser = 'hafiz_session_user_v1';

class SyncOp {
  SyncOp({
    required this.id,
    required this.type,
    required this.payload,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      };

  factory SyncOp.fromJson(Map<String, dynamic> json) => SyncOp(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class LocalSnapshot {
  LocalSnapshot({
    required this.mosques,
    required this.admins,
    required this.teachers,
    required this.students,
    required this.homework,
    required this.progress,
    required this.lastMemorization,
    this.todaySession,
    required this.attendance,
    this.currentUser,
    this.currentMosqueId,
  });

  final List<Map<String, dynamic>> mosques;
  final List<Map<String, dynamic>> admins;
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> students;
  final Map<String, Map<String, dynamic>> homework;
  final Map<String, Map<String, dynamic>> progress;
  final Map<String, String> lastMemorization;
  final Map<String, dynamic>? todaySession;
  final List<Map<String, dynamic>> attendance;
  final Map<String, dynamic>? currentUser;
  final String? currentMosqueId;

  Map<String, dynamic> toJson() => {
        'mosques': mosques,
        'admins': admins,
        'teachers': teachers,
        'students': students,
        'homework': homework,
        'progress': progress,
        'last_memorization': lastMemorization,
        'today_session': todaySession,
        'attendance': attendance,
        'current_user': currentUser,
        'current_mosque_id': currentMosqueId,
      };

  factory LocalSnapshot.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, dynamic>> nest(dynamic raw) {
      final map = <String, Map<String, dynamic>>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) map[k.toString()] = Map<String, dynamic>.from(v);
        });
      }
      return map;
    }

    Map<String, String> stringMap(dynamic raw) {
      final map = <String, String>{};
      if (raw is Map) {
        raw.forEach((k, v) => map[k.toString()] = v.toString());
      }
      return map;
    }

    List<Map<String, dynamic>> list(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return LocalSnapshot(
      mosques: list(json['mosques']),
      admins: list(json['admins']),
      teachers: list(json['teachers']),
      students: list(json['students']),
      homework: nest(json['homework']),
      progress: nest(json['progress']),
      lastMemorization: stringMap(json['last_memorization']),
      todaySession: json['today_session'] is Map
          ? Map<String, dynamic>.from(json['today_session'] as Map)
          : null,
      attendance: list(json['attendance']),
      currentUser: json['current_user'] is Map
          ? Map<String, dynamic>.from(json['current_user'] as Map)
          : null,
      currentMosqueId: json['current_mosque_id'] as String?,
    );
  }
}

class LocalStore {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<LocalSnapshot?> loadSnapshot() async {
    await init();
    final raw = _prefs!.getString(_kSnapshot);
    if (raw == null || raw.isEmpty) return null;
    try {
      return LocalSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(LocalSnapshot snapshot) async {
    await init();
    await _prefs!.setString(_kSnapshot, jsonEncode(snapshot.toJson()));
  }

  Future<List<SyncOp>> loadQueue() async {
    await init();
    final raw = _prefs!.getString(_kSyncQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => SyncOp.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQueue(List<SyncOp> ops) async {
    await init();
    await _prefs!.setString(
      _kSyncQueue,
      jsonEncode(ops.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearSession() async {
    await init();
    await _prefs!.remove(_kSessionUser);
  }
}

String attendanceStatusWire(AttendanceStatus s) => switch (s) {
      AttendanceStatus.unmarked => 'unmarked',
      AttendanceStatus.present => 'present',
      AttendanceStatus.absent => 'absent',
      AttendanceStatus.late => 'late',
    };

AttendanceStatus attendanceStatusFromWire(String? s) => switch (s) {
      'present' => AttendanceStatus.present,
      'absent' => AttendanceStatus.absent,
      'late' => AttendanceStatus.late,
      _ => AttendanceStatus.unmarked,
    };

String memorizationWire(MemorizationLevel l) => switch (l) {
      MemorizationLevel.notMemorized => 'not_memorized',
      MemorizationLevel.poor => 'poor',
      MemorizationLevel.average => 'average',
      MemorizationLevel.good => 'good',
      MemorizationLevel.veryGood => 'very_good',
      MemorizationLevel.excellent => 'excellent',
    };

MemorizationLevel memorizationFromWire(String? s) => switch (s) {
      'poor' => MemorizationLevel.poor,
      'average' => MemorizationLevel.average,
      'good' => MemorizationLevel.good,
      'very_good' => MemorizationLevel.veryGood,
      'excellent' => MemorizationLevel.excellent,
      _ => MemorizationLevel.notMemorized,
    };

String sessionStatusWire(SessionStatus s) => switch (s) {
      SessionStatus.active => 'active',
      SessionStatus.completed => 'completed',
      SessionStatus.cancelled => 'cancelled',
    };

SessionStatus sessionStatusFromWire(String? s) => switch (s) {
      'completed' => SessionStatus.completed,
      'cancelled' => SessionStatus.cancelled,
      _ => SessionStatus.active,
    };

String roleWire(UserRole r) => switch (r) {
      UserRole.mosqueAdmin => 'mosque_admin',
      UserRole.teacher => 'teacher',
      UserRole.student => 'student',
    };

UserRole roleFromWire(String? s) => switch (s) {
      'teacher' => UserRole.teacher,
      'student' => UserRole.student,
      _ => UserRole.mosqueAdmin,
    };
