import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/utils/code_generators.dart';
import '../../core/utils/id_utils.dart';
import '../../core/utils/whatsapp_report.dart';
import '../local/local_store.dart';
import '../models/models.dart';
import '../quran/quran_repository.dart';
import '../quran/tafsir_muyassar.dart';
import '../remote/api_client.dart';

final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  return QuranRepository();
});

final tafsirMuyassarProvider = Provider<TafsirMuyassarRepository>((ref) {
  return TafsirMuyassarRepository();
});

final quranReadyProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.watch(quranRepositoryProvider).load(),
    ref.watch(tafsirMuyassarProvider).load(),
  ]);
});

enum SyncFailureKind { offline, auth, api, unknown }

class SyncException implements Exception {
  SyncException(this.message, {this.kind = SyncFailureKind.unknown});

  final String message;
  final SyncFailureKind kind;

  @override
  String toString() => message;
}

class DemoHafizRepository {
  DemoHafizRepository({
    LocalStore? store,
    ApiClient? api,
    bool seedDemoData = true,
  })  : _store = store ?? LocalStore(),
        _api = api ?? ApiClient(),
        _seedDemoData = seedDemoData;

  final LocalStore _store;
  final ApiClient _api;
  final bool _seedDemoData;
  final _uuid = const Uuid();
  final _codes = CodeGenerators();
  final List<SyncOp> _syncQueue = [];

  AppUser? currentUser;
  Mosque? currentMosque;

  final List<Mosque> mosques = [];
  final Map<String, _AdminCreds> _admins = {};
  final List<TeacherAccount> teachers = [];
  final List<StudentProfile> students = [];
  ClassSession? todaySession;
  final List<AttendanceRecord> attendance = [];
  final Map<String, StudentHomework> homeworkByStudent = {};
  final List<HomeworkAssignment> homeworkAssignments = [];
  final Map<String, ReadingProgress> progressByStudent = {};
  final Map<String, MemorizationLevel> lastMemorizationByStudent = {};
  TeacherClassSchedule? classSchedule;
  final List<ClassSession> sessionHistory = [];
  final List<LessonArchiveRow> attendanceHistory = [];

  int get pendingSyncCount => _syncQueue.length;
  bool get apiConfigured => _api.isConfigured;

  /// استعادة الحالة من التخزين المحلي، أو زرع بيانات تجريبية إن لم يوجد شيء.
  Future<void> restore() async {
    await _store.init();
    final snap = await _store.loadSnapshot();
    _syncQueue
      ..clear()
      ..addAll(await _store.loadQueue());
    if (snap == null) {
      if (_seedDemoData) _seed();
      await persistLocal();
    } else {
      _applySnapshot(snap);
    }
  }

  Future<void> persistLocal() async {
    await _store.saveSnapshot(_toSnapshot());
    await _store.saveQueue(List.unmodifiable(_syncQueue));
  }

  void _enqueue(String type, Map<String, dynamic> payload) {
    _syncQueue.add(
      SyncOp(id: _uuid.v4(), type: type, payload: payload),
    );
  }

  Future<void> _afterWrite({SyncOp? op}) async {
    if (op != null) _syncQueue.add(op);
    await persistLocal();
    if (SupabaseConfig.isConfigured) {
      try {
        await flushSyncQueue();
      } catch (_) {
        // تبقى في الطابور للمزامنة لاحقًا
      }
    }
  }

  Future<void> _applyAuthSession({
    required AppUser user,
    required Mosque mosque,
    TeacherAccount? teacher,
    StudentProfile? student,
    _AdminCreds? admin,
  }) async {
    if (teacher != null) {
      teachers.removeWhere((t) => t.id == teacher.id);
      teachers.add(teacher);
    }
    if (student != null) {
      students.removeWhere((s) => s.id == student.id);
      students.add(student);
    }
    if (admin != null) {
      _admins[admin.email] = admin;
    }
    mosques.removeWhere((m) => m.id == mosque.id);
    mosques.add(mosque);
    currentUser = user;
    currentMosque = mosque;
    await persistLocal();
    // بعد تسجيل الدخول: ادفع الطابور ثم اسحب أحدث لقطة
    try {
      await flushSyncQueue();
    } catch (_) {}
    try {
      await pullFromServer(mosque.id);
    } catch (_) {}
  }

  bool _looksLikeNetworkFailure(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('handshake');
  }

  Future<String> flushSyncQueue() async {
    if (!SupabaseConfig.isConfigured) return 'الخادم غير مضبوط';
    if (_syncQueue.isEmpty) return 'لا عمليات معلّقة — البيانات محفوظة محليًا';

    final pending = _syncQueue.length;
    if (!_api.hasHafizToken) {
      await persistLocal();
      throw SyncException(
        'يلزم تسجيل الدخول لإرسال $pending عملية معلّقة',
        kind: SyncFailureKind.auth,
      );
    }

    try {
      // حوّل معرفات تجريبية مثل stu-1 إلى UUID قبل الإرسال
      final batch = _syncQueue.map((op) {
        return SyncOp(
          id: op.id,
          type: op.type,
          payload: sanitizeSyncPayload(Map<String, dynamic>.from(op.payload)),
          createdAt: op.createdAt,
        );
      }).toList();
      final res = await _api.pushOps(batch);
      final errors = (res['errors'] as List?) ?? const [];
      if (errors.isEmpty) {
        _syncQueue.clear();
      } else {
        final failedIds = errors
            .whereType<Map>()
            .map((e) => e['id']?.toString())
            .whereType<String>()
            .toSet();
        _syncQueue.removeWhere((op) => !failedIds.contains(op.id));
      }
      await persistLocal();

      // سحب لقطة المسجد إن وُجد مستخدم
      final mosqueId = currentUser?.mosqueId ?? currentMosque?.id;
      if (mosqueId != null && mosqueId.isNotEmpty) {
        try {
          await pullFromServer(mosqueId);
        } catch (_) {}
      }

      if (errors.isNotEmpty) {
        String? detail;
        for (final e in errors.whereType<Map>()) {
          final raw = e['error'];
          String err = '';
          if (raw is String) {
            err = raw.trim();
          } else if (raw is Map) {
            err = (raw['message'] ?? raw['error'] ?? raw).toString().trim();
          } else if (raw != null) {
            err = raw.toString().trim();
          }
          if (err.isNotEmpty && err != '[object Object]') {
            detail = err;
            break;
          }
        }
        if (detail != null) {
          return 'مزامنة جزئية — ${errors.length} أخطاء: $detail';
        }
        return 'مزامنة جزئية — ${errors.length} أخطاء (الباقي محفوظ محليًا)';
      }
      return 'تمت المزامنة مع الخادم بنجاح';
    } on SyncException {
      rethrow;
    } on ApiException catch (e) {
      await persistLocal();
      if (e.statusCode == 401 || e.statusCode == 403) {
        throw SyncException(
          'انتهت الجلسة — سجّل الدخول لإرسال $pending عملية معلّقة',
          kind: SyncFailureKind.auth,
        );
      }
      throw SyncException(
        'خطأ من الخادم أثناء المزامنة: ${e.message}',
        kind: SyncFailureKind.api,
      );
    } catch (e) {
      await persistLocal();
      if (_looksLikeNetworkFailure(e)) {
        // تأكيد الوصول: إن فشل /health أيضًا نعرض رسالة الشبكة
        final reachable = await _api.healthCheck();
        if (!reachable) {
          throw SyncException(
            'تعذّر الوصول للخادم — تحقق من الإنترنت ($pending عملية محفوظة محليًا)',
            kind: SyncFailureKind.offline,
          );
        }
        throw SyncException(
          'تعذّرت المزامنة رغم الاتصال — أعد المحاولة ($pending عملية محفوظة)',
          kind: SyncFailureKind.api,
        );
      }
      throw SyncException(
        'تعذّرت المزامنة — البيانات ما زالت محفوظة محليًا',
        kind: SyncFailureKind.unknown,
      );
    }
  }

  Future<void> pullFromServer(String mosqueId) async {
    final data = await _api.pullMosque(mosqueId);
    _mergeServerSnapshot(data);
    await persistLocal();
  }

  void _mergeServerSnapshot(Map<String, dynamic> data) {
    final mosqueMap = data['mosque'];
    if (mosqueMap is Map) {
      final m = Map<String, dynamic>.from(mosqueMap);
      final id = m['id']?.toString() ?? '';
      final name = m['name']?.toString() ?? '';
      if (id.isNotEmpty) {
        mosques.removeWhere((x) => x.id == id);
        mosques.add(
          Mosque(
            id: id,
            name: name,
            createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        );
      }
    }

    final serverTeachers = (data['teachers'] as List?) ?? const [];
    for (final raw in serverTeachers.whereType<Map>()) {
      final t = Map<String, dynamic>.from(raw);
      final id = t['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      teachers.removeWhere((x) => x.id == id);
      teachers.add(
        TeacherAccount(
          id: id,
          fullName: t['full_name']?.toString() ?? '',
          englishName: t['english_name']?.toString() ?? '',
          englishPrefix: t['english_prefix']?.toString() ?? 'XX',
          loginCode: t['login_code']?.toString() ?? '',
          mosqueId: t['mosque_id']?.toString() ?? '',
        ),
      );
    }

    final serverStudents = (data['students'] as List?) ?? const [];
    for (final raw in serverStudents.whereType<Map>()) {
      final s = Map<String, dynamic>.from(raw);
      final id = s['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      students.removeWhere((x) => x.id == id);
      students.add(
        StudentProfile(
          id: id,
          fullName: s['full_name']?.toString() ?? '',
          gradeLevel: s['grade_level']?.toString() ?? '',
          age: int.tryParse(s['age']?.toString() ?? '') ?? 0,
          parentPhone: s['parent_phone']?.toString() ?? '',
          mosqueId: s['mosque_id']?.toString() ?? '',
          teacherId: s['teacher_id']?.toString() ?? '',
          loginUsername: s['login_username']?.toString() ?? '',
          loginCode: s['login_code']?.toString() ?? '',
        ),
      );
    }

    final serverAssignments =
        (data['homework_assignments'] as List?) ?? const [];
    for (final raw in serverAssignments.whereType<Map>()) {
      final h = Map<String, dynamic>.from(raw);
      final id = h['id']?.toString() ?? '';
      final sid = h['student_id']?.toString() ?? '';
      if (id.isEmpty || sid.isEmpty) continue;
      homeworkAssignments.removeWhere((a) => a.id == id);
      homeworkAssignments.add(
        HomeworkAssignment(
          id: id,
          studentId: sid,
          sessionId: h['session_id']?.toString(),
          surahNumber:
              int.tryParse(h['surah_number']?.toString() ?? '') ?? 1,
          fromAyah: int.tryParse(h['from_ayah']?.toString() ?? '') ?? 1,
          toAyah: int.tryParse(h['to_ayah']?.toString() ?? '') ?? 1,
          note: h['note']?.toString() ?? '',
          assignedAt:
              DateTime.tryParse(h['assigned_at']?.toString() ?? '') ??
                  DateTime.now(),
        ),
      );
    }

    final serverHw = (data['student_homework'] as List?) ?? const [];
    for (final raw in serverHw.whereType<Map>()) {
      final h = Map<String, dynamic>.from(raw);
      final sid = h['student_id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      homeworkByStudent[sid] = StudentHomework(
        id: h['id']?.toString() ?? _uuid.v4(),
        studentId: sid,
        surahNumber: int.tryParse(h['surah_number']?.toString() ?? '') ?? 1,
        fromAyah: int.tryParse(h['from_ayah']?.toString() ?? '') ?? 1,
        toAyah: int.tryParse(h['to_ayah']?.toString() ?? '') ?? 1,
        note: h['note']?.toString() ?? '',
        assignedAt:
            DateTime.tryParse(h['assigned_at']?.toString() ?? '') ??
                DateTime.now(),
      );
    }

    final serverProgress = (data['progress'] as List?) ?? const [];
    for (final raw in serverProgress.whereType<Map>()) {
      final p = Map<String, dynamic>.from(raw);
      final sid = p['student_id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      progressByStudent[sid] = ReadingProgress(
        studentId: sid,
        surahNumber: int.tryParse(p['surah_number']?.toString() ?? '') ?? 1,
        ayahNumber: int.tryParse(p['ayah_number']?.toString() ?? '') ?? 1,
      );
    }

    _mergeServerSessions(data);
    _mergeServerSchedules(data);
  }

  void _mergeServerSchedules(Map<String, dynamic> data) {
    final list = (data['teacher_class_schedules'] as List?) ?? const [];
    final me = currentUser;
    if (me == null) return;

    String? teacherId;
    if (me.role == UserRole.teacher) {
      teacherId = me.id;
    } else if (me.role == UserRole.student) {
      for (final s in students) {
        if (s.id == me.id) {
          teacherId = s.teacherId;
          break;
        }
      }
    }

    TeacherClassSchedule? found;
    for (final raw in list.whereType<Map>()) {
      final m = Map<String, dynamic>.from(raw);
      final tid = m['teacher_id']?.toString() ?? '';
      if (teacherId != null && tid != teacherId) continue;
      final daysRaw = m['weekdays'];
      final days = <int>[];
      if (daysRaw is List) {
        for (final d in daysRaw) {
          final n = int.tryParse(d.toString());
          if (n != null && n >= 1 && n <= 7) days.add(n);
        }
      }
      days.sort();
      found = TeacherClassSchedule(
        id: m['id']?.toString() ?? _uuid.v4(),
        mosqueId: m['mosque_id']?.toString() ?? me.mosqueId,
        teacherId: tid,
        lecturesPerWeek:
            int.tryParse(m['lectures_per_week']?.toString() ?? '') ??
                days.length,
        weekdays: days,
        active: m['active'] != false,
      );
      break;
    }
    if (found != null) classSchedule = found;
  }

  String _studentNameById(String id) {
    for (final s in students) {
      if (s.id == id) return s.fullName;
    }
    return '';
  }

  /// طلاب لديهم تعديل حضور لم يُرفع بعد؛ لا نستبدل تعديلهم بنسخة الخادم.
  Set<String> _pendingAttendanceStudentIds() {
    final ids = <String>{};
    for (final op in _syncQueue) {
      if (op.type != 'upsert_attendance') continue;
      final sid = op.payload['student_id']?.toString();
      if (sid != null && sid.isNotEmpty) ids.add(sid);
    }
    return ids;
  }

  /// دمج الجلسات والحضور من الخادم ليظهر عمل اليوم على بقية الأجهزة.
  void _mergeServerSessions(Map<String, dynamic> data) {
    final serverSessions = (data['sessions'] as List?) ?? const [];
    final serverAttendance = (data['attendance'] as List?) ?? const [];
    if (serverSessions.isEmpty && serverAttendance.isEmpty) return;

    final pending = _pendingAttendanceStudentIds();
    final me = currentUser;

    final sessionDateById = <String, DateTime>{};
    final sessionById = <String, Map<String, dynamic>>{};
    for (final raw in serverSessions.whereType<Map>()) {
      final s = Map<String, dynamic>.from(raw);
      final id = s['id']?.toString() ?? '';
      final date = DateTime.tryParse(s['session_date']?.toString() ?? '');
      if (id.isEmpty || date == null) continue;
      sessionDateById[id] = DateTime(date.year, date.month, date.day);
      sessionById[id] = s;
    }

    // أرشيف محلي من لقطة الخادم (معزولة مسبقًا حسب الدور في الـ API).
    final histSessions = <ClassSession>[];
    for (final s in sessionById.values) {
      final id = s['id']?.toString() ?? '';
      final date = sessionDateById[id];
      if (id.isEmpty || date == null) continue;
      histSessions.add(
        ClassSession(
          id: id,
          mosqueId: s['mosque_id']?.toString() ?? me?.mosqueId ?? '',
          teacherId: s['teacher_id']?.toString() ?? '',
          sessionDate: date,
          status: sessionStatusFromWire(s['status']?.toString()),
          startedAt:
              DateTime.tryParse(s['started_at']?.toString() ?? '') ?? date,
          endedAt: DateTime.tryParse(s['ended_at']?.toString() ?? ''),
        ),
      );
    }
    histSessions.sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
    sessionHistory
      ..clear()
      ..addAll(histSessions);

    final histRows = <LessonArchiveRow>[];
    for (final raw in serverAttendance.whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      final sid = a['student_id']?.toString() ?? '';
      final sessionId = a['session_id']?.toString() ?? '';
      final date = sessionDateById[sessionId];
      if (sid.isEmpty || sessionId.isEmpty || date == null) continue;
      final wire = a['memorization_level']?.toString();
      histRows.add(
        LessonArchiveRow(
          sessionId: sessionId,
          sessionDate: date,
          studentId: sid,
          studentName: _studentNameById(sid),
          status: attendanceStatusFromWire(a['status']?.toString()),
          memorizationLevel:
              wire == null || wire.isEmpty ? null : memorizationFromWire(wire),
          behaviorScore: int.tryParse(a['behavior_score']?.toString() ?? ''),
        ),
      );
    }
    histRows.sort((a, b) {
      final byDate = b.sessionDate.compareTo(a.sessionDate);
      if (byDate != 0) return byDate;
      return a.studentName.compareTo(b.studentName);
    });
    attendanceHistory
      ..clear()
      ..addAll(histRows);

    // آخر تقييم حفظ لكل طالب عبر كل الجلسات (تعتمده لوحات المتابعة).
    final latestLevelDate = <String, DateTime>{};
    for (final raw in serverAttendance.whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      final sid = a['student_id']?.toString() ?? '';
      final wire = a['memorization_level']?.toString();
      if (sid.isEmpty || wire == null || wire.isEmpty) continue;
      if (pending.contains(sid)) continue;
      final date = sessionDateById[a['session_id']?.toString() ?? ''];
      if (date == null) continue;
      final seen = latestLevelDate[sid];
      if (seen != null && !date.isAfter(seen)) continue;
      latestLevelDate[sid] = date;
      lastMemorizationByStudent[sid] = memorizationFromWire(wire);
    }

    if (me == null || me.role != UserRole.teacher) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Map<String, dynamic>? serverToday;
    for (final s in sessionById.values) {
      if (s['teacher_id']?.toString() != me.id) continue;
      final date = sessionDateById[s['id']?.toString() ?? ''];
      if (date == null) continue;
      if (date.year != today.year ||
          date.month != today.month ||
          date.day != today.day) {
        continue;
      }
      serverToday = s;
      break;
    }
    if (serverToday == null) return;

    final sessionId = serverToday['id']?.toString() ?? '';
    if (sessionId.isEmpty) return;
    todaySession = ClassSession(
      id: sessionId,
      mosqueId: serverToday['mosque_id']?.toString() ?? me.mosqueId,
      teacherId: me.id,
      sessionDate: today,
      status: sessionStatusFromWire(serverToday['status']?.toString()),
      startedAt:
          DateTime.tryParse(serverToday['started_at']?.toString() ?? '') ??
              today,
      endedAt: DateTime.tryParse(serverToday['ended_at']?.toString() ?? ''),
    );

    final localByStudent = {for (final a in attendance) a.studentId: a};
    final merged = <AttendanceRecord>[];
    for (final raw in serverAttendance.whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      if (a['session_id']?.toString() != sessionId) continue;
      final sid = a['student_id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      final local = localByStudent.remove(sid);
      if (local != null && pending.contains(sid)) {
        merged.add(local);
        continue;
      }
      final wire = a['memorization_level']?.toString();
      merged.add(
        AttendanceRecord(
          id: a['id']?.toString() ?? local?.id ?? _uuid.v4(),
          sessionId: sessionId,
          studentId: sid,
          studentName: local?.studentName ?? _studentNameById(sid),
          status: attendanceStatusFromWire(a['status']?.toString()),
          memorizationLevel: wire == null || wire.isEmpty
              ? null
              : memorizationFromWire(wire),
          behaviorScore: int.tryParse(a['behavior_score']?.toString() ?? ''),
          evaluationConfirmedAt: DateTime.tryParse(
            a['evaluation_confirmed_at']?.toString() ?? '',
          ),
        ),
      );
    }
    merged.addAll(localByStudent.values);
    attendance
      ..clear()
      ..addAll(merged);
    _syncAttendanceRoster();
  }

  LocalSnapshot _toSnapshot() {
    return LocalSnapshot(
      mosques: mosques
          .map(
            (m) => {
              'id': m.id,
              'name': m.name,
              'created_at': m.createdAt.toIso8601String(),
            },
          )
          .toList(),
      admins: _admins.values
          .map(
            (a) => {
              'id': a.id,
              'full_name': a.fullName,
              'email': a.email,
              'password': a.password,
              'mosque_id': a.mosqueId,
            },
          )
          .toList(),
      teachers: teachers
          .map(
            (t) => {
              'id': t.id,
              'full_name': t.fullName,
              'english_name': t.englishName,
              'english_prefix': t.englishPrefix,
              'login_code': t.loginCode,
              'mosque_id': t.mosqueId,
            },
          )
          .toList(),
      students: students
          .map(
            (s) => {
              'id': s.id,
              'full_name': s.fullName,
              'grade_level': s.gradeLevel,
              'age': s.age,
              'parent_phone': s.parentPhone,
              'mosque_id': s.mosqueId,
              'teacher_id': s.teacherId,
              'login_username': s.loginUsername,
              'login_code': s.loginCode,
            },
          )
          .toList(),
      homework: {
        for (final e in homeworkByStudent.entries)
          e.key: {
            'id': e.value.id,
            'student_id': e.value.studentId,
            'surah_number': e.value.surahNumber,
            'from_ayah': e.value.fromAyah,
            'to_ayah': e.value.toAyah,
            'note': e.value.note,
            'assigned_at': e.value.assignedAt.toIso8601String(),
          },
      },
      homeworkAssignments: homeworkAssignments
          .map(
            (a) => {
              'id': a.id,
              'student_id': a.studentId,
              'session_id': a.sessionId,
              'surah_number': a.surahNumber,
              'from_ayah': a.fromAyah,
              'to_ayah': a.toAyah,
              'note': a.note,
              'assigned_at': a.assignedAt.toIso8601String(),
            },
          )
          .toList(),
      progress: {
        for (final e in progressByStudent.entries)
          e.key: {
            'student_id': e.value.studentId,
            'surah_number': e.value.surahNumber,
            'ayah_number': e.value.ayahNumber,
          },
      },
      lastMemorization: {
        for (final e in lastMemorizationByStudent.entries)
          e.key: memorizationWire(e.value),
      },
      todaySession: todaySession == null
          ? null
          : {
              'id': todaySession!.id,
              'mosque_id': todaySession!.mosqueId,
              'teacher_id': todaySession!.teacherId,
              'session_date': todaySession!.sessionDate.toIso8601String(),
              'status': sessionStatusWire(todaySession!.status),
              'started_at': todaySession!.startedAt.toIso8601String(),
              if (todaySession!.endedAt != null)
                'ended_at': todaySession!.endedAt!.toIso8601String(),
            },
      attendance: attendance
          .map(
            (a) => {
              'id': a.id,
              'session_id': a.sessionId,
              'student_id': a.studentId,
              'student_name': a.studentName,
              'status': attendanceStatusWire(a.status),
              'memorization_level': a.memorizationLevel == null
                  ? null
                  : memorizationWire(a.memorizationLevel!),
              'behavior_score': a.behaviorScore,
              if (a.evaluationConfirmedAt != null)
                'evaluation_confirmed_at':
                    a.evaluationConfirmedAt!.toIso8601String(),
            },
          )
          .toList(),
      classSchedule: classSchedule == null
          ? null
          : {
              'id': classSchedule!.id,
              'mosque_id': classSchedule!.mosqueId,
              'teacher_id': classSchedule!.teacherId,
              'lectures_per_week': classSchedule!.lecturesPerWeek,
              'weekdays': classSchedule!.weekdays,
              'active': classSchedule!.active,
            },
      sessionHistory: sessionHistory
          .map(
            (s) => {
              'id': s.id,
              'mosque_id': s.mosqueId,
              'teacher_id': s.teacherId,
              'session_date': s.sessionDate.toIso8601String(),
              'status': sessionStatusWire(s.status),
              'started_at': s.startedAt.toIso8601String(),
              if (s.endedAt != null) 'ended_at': s.endedAt!.toIso8601String(),
            },
          )
          .toList(),
      attendanceHistory: attendanceHistory
          .map(
            (a) => {
              'session_id': a.sessionId,
              'session_date': a.sessionDate.toIso8601String(),
              'student_id': a.studentId,
              'student_name': a.studentName,
              'status': attendanceStatusWire(a.status),
              'memorization_level': a.memorizationLevel == null
                  ? null
                  : memorizationWire(a.memorizationLevel!),
              'behavior_score': a.behaviorScore,
            },
          )
          .toList(),
      currentUser: currentUser == null
          ? null
          : {
              'id': currentUser!.id,
              'full_name': currentUser!.fullName,
              'role': roleWire(currentUser!.role),
              'mosque_id': currentUser!.mosqueId,
              'email': currentUser!.email,
            },
      currentMosqueId: currentMosque?.id,
    );
  }

  void _applySnapshot(LocalSnapshot snap) {
    mosques
      ..clear()
      ..addAll(
        snap.mosques.map(
          (m) => Mosque(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
            createdAt:
                DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                    DateTime.now(),
          ),
        ),
      );

    _admins.clear();
    for (final a in snap.admins) {
      final email = a['email']?.toString() ?? '';
      if (email.isEmpty) continue;
      _admins[email] = _AdminCreds(
        id: a['id']?.toString() ?? '',
        fullName: a['full_name']?.toString() ?? '',
        email: email,
        password: a['password']?.toString() ?? '',
        mosqueId: a['mosque_id']?.toString() ?? '',
      );
    }

    teachers
      ..clear()
      ..addAll(
        snap.teachers.map(
          (t) => TeacherAccount(
            id: t['id']?.toString() ?? '',
            fullName: t['full_name']?.toString() ?? '',
            englishName: t['english_name']?.toString() ?? '',
            englishPrefix: t['english_prefix']?.toString() ?? 'XX',
            loginCode: t['login_code']?.toString() ?? '',
            mosqueId: t['mosque_id']?.toString() ?? '',
          ),
        ),
      );

    students
      ..clear()
      ..addAll(
        snap.students.map(
          (s) => StudentProfile(
            id: s['id']?.toString() ?? '',
            fullName: s['full_name']?.toString() ?? '',
            gradeLevel: s['grade_level']?.toString() ?? '',
            age: int.tryParse(s['age']?.toString() ?? '') ?? 0,
            parentPhone: s['parent_phone']?.toString() ?? '',
            mosqueId: s['mosque_id']?.toString() ?? '',
            teacherId: s['teacher_id']?.toString() ?? '',
            loginUsername: s['login_username']?.toString() ?? '',
            loginCode: s['login_code']?.toString() ?? '',
          ),
        ),
      );

    homeworkByStudent
      ..clear()
      ..addAll({
        for (final e in snap.homework.entries)
          e.key: StudentHomework(
            id: e.value['id']?.toString() ?? '',
            studentId: e.value['student_id']?.toString() ?? e.key,
            surahNumber:
                int.tryParse(e.value['surah_number']?.toString() ?? '') ?? 1,
            fromAyah:
                int.tryParse(e.value['from_ayah']?.toString() ?? '') ?? 1,
            toAyah: int.tryParse(e.value['to_ayah']?.toString() ?? '') ?? 1,
            note: e.value['note']?.toString() ?? '',
            assignedAt: DateTime.tryParse(
                  e.value['assigned_at']?.toString() ?? '',
                ) ??
                DateTime.now(),
          ),
      });

    homeworkAssignments
      ..clear()
      ..addAll(
        snap.homeworkAssignments.map(
          (a) => HomeworkAssignment(
            id: a['id']?.toString() ?? '',
            studentId: a['student_id']?.toString() ?? '',
            sessionId: a['session_id']?.toString(),
            surahNumber:
                int.tryParse(a['surah_number']?.toString() ?? '') ?? 1,
            fromAyah: int.tryParse(a['from_ayah']?.toString() ?? '') ?? 1,
            toAyah: int.tryParse(a['to_ayah']?.toString() ?? '') ?? 1,
            note: a['note']?.toString() ?? '',
            assignedAt: DateTime.tryParse(
                  a['assigned_at']?.toString() ?? '',
                ) ??
                DateTime.now(),
          ),
        ),
      );

    progressByStudent
      ..clear()
      ..addAll({
        for (final e in snap.progress.entries)
          e.key: ReadingProgress(
            studentId: e.value['student_id']?.toString() ?? e.key,
            surahNumber:
                int.tryParse(e.value['surah_number']?.toString() ?? '') ?? 1,
            ayahNumber:
                int.tryParse(e.value['ayah_number']?.toString() ?? '') ?? 1,
          ),
      });

    lastMemorizationByStudent
      ..clear()
      ..addAll({
        for (final e in snap.lastMemorization.entries)
          e.key: memorizationFromWire(e.value),
      });

    if (snap.todaySession != null) {
      final s = snap.todaySession!;
      todaySession = ClassSession(
        id: s['id']?.toString() ?? '',
        mosqueId: s['mosque_id']?.toString() ?? '',
        teacherId: s['teacher_id']?.toString() ?? '',
        sessionDate:
            DateTime.tryParse(s['session_date']?.toString() ?? '') ??
                DateTime.now(),
        status: sessionStatusFromWire(s['status']?.toString()),
        startedAt:
            DateTime.tryParse(s['started_at']?.toString() ?? '') ??
                DateTime.now(),
        endedAt: DateTime.tryParse(s['ended_at']?.toString() ?? ''),
      );
    } else {
      todaySession = null;
    }

    attendance
      ..clear()
      ..addAll(
        snap.attendance.map(
          (a) => AttendanceRecord(
            id: a['id']?.toString() ?? '',
            sessionId: a['session_id']?.toString() ?? '',
            studentId: a['student_id']?.toString() ?? '',
            studentName: a['student_name']?.toString() ?? '',
            status: attendanceStatusFromWire(a['status']?.toString()),
            memorizationLevel: a['memorization_level'] == null
                ? null
                : memorizationFromWire(a['memorization_level']?.toString()),
            behaviorScore: a['behavior_score'] == null
                ? null
                : int.tryParse(a['behavior_score'].toString()),
            evaluationConfirmedAt: DateTime.tryParse(
              a['evaluation_confirmed_at']?.toString() ?? '',
            ),
          ),
        ),
      );

    if (snap.classSchedule != null) {
      final c = snap.classSchedule!;
      final days = <int>[];
      final rawDays = c['weekdays'];
      if (rawDays is List) {
        for (final d in rawDays) {
          final n = int.tryParse(d.toString());
          if (n != null && n >= 1 && n <= 7) days.add(n);
        }
      }
      days.sort();
      classSchedule = TeacherClassSchedule(
        id: c['id']?.toString() ?? '',
        mosqueId: c['mosque_id']?.toString() ?? '',
        teacherId: c['teacher_id']?.toString() ?? '',
        lecturesPerWeek:
            int.tryParse(c['lectures_per_week']?.toString() ?? '') ??
                days.length,
        weekdays: days,
        active: c['active'] != false,
      );
    } else {
      classSchedule = null;
    }

    sessionHistory
      ..clear()
      ..addAll(
        snap.sessionHistory.map(
          (s) => ClassSession(
            id: s['id']?.toString() ?? '',
            mosqueId: s['mosque_id']?.toString() ?? '',
            teacherId: s['teacher_id']?.toString() ?? '',
            sessionDate:
                DateTime.tryParse(s['session_date']?.toString() ?? '') ??
                    DateTime.now(),
            status: sessionStatusFromWire(s['status']?.toString()),
            startedAt:
                DateTime.tryParse(s['started_at']?.toString() ?? '') ??
                    DateTime.now(),
            endedAt: DateTime.tryParse(s['ended_at']?.toString() ?? ''),
          ),
        ),
      );

    attendanceHistory
      ..clear()
      ..addAll(
        snap.attendanceHistory.map(
          (a) {
            final wire = a['memorization_level']?.toString();
            return LessonArchiveRow(
              sessionId: a['session_id']?.toString() ?? '',
              sessionDate:
                  DateTime.tryParse(a['session_date']?.toString() ?? '') ??
                      DateTime.now(),
              studentId: a['student_id']?.toString() ?? '',
              studentName: a['student_name']?.toString() ?? '',
              status: attendanceStatusFromWire(a['status']?.toString()),
              memorizationLevel: wire == null || wire.isEmpty
                  ? null
                  : memorizationFromWire(wire),
              behaviorScore: a['behavior_score'] == null
                  ? null
                  : int.tryParse(a['behavior_score'].toString()),
            );
          },
        ),
      );

    if (snap.currentUser != null) {
      final u = snap.currentUser!;
      currentUser = AppUser(
        id: u['id']?.toString() ?? '',
        fullName: u['full_name']?.toString() ?? '',
        role: roleFromWire(u['role']?.toString()),
        mosqueId: u['mosque_id']?.toString() ?? '',
        email: u['email']?.toString() ?? '',
      );
    } else {
      currentUser = null;
    }

    currentMosque = snap.currentMosqueId == null
        ? null
        : mosqueById(snap.currentMosqueId!);
  }

  void _seed() {
    final mosqueId = ensureUuid('mosque-1');
    final adminId = ensureUuid('admin-1');
    final teacherId = ensureUuid('teacher-1');
    final stu1 = ensureUuid('stu-1');
    final stu2 = ensureUuid('stu-2');
    final hw1 = ensureUuid('hw-1');

    final mosque = Mosque(
      id: mosqueId,
      name: 'مسجد النور',
      createdAt: DateTime.now(),
    );
    mosques.add(mosque);

    _admins['admin@demo.local'] = _AdminCreds(
      id: adminId,
      fullName: 'إدارة مسجد النور',
      email: 'admin@demo.local',
      password: 'demo1234',
      mosqueId: mosque.id,
    );

    teachers.add(
      TeacherAccount(
        id: teacherId,
        fullName: 'الشيخ إبراهيم',
        englishName: 'Ibrahim',
        englishPrefix: 'IB',
        loginCode: 'IB482917',
        mosqueId: mosqueId,
      ),
    );

    students.addAll([
      StudentProfile(
        id: stu1,
        fullName: 'أحمد يوسف',
        gradeLevel: 'الصف الخامس',
        age: 11,
        parentPhone: '0511111111',
        mosqueId: mosqueId,
        teacherId: teacherId,
        loginUsername: 'ahmad_yusuf',
        loginCode: 'A7K3M',
      ),
      StudentProfile(
        id: stu2,
        fullName: 'محمد خالد',
        gradeLevel: 'الصف السادس',
        age: 12,
        parentPhone: '0522222222',
        mosqueId: mosqueId,
        teacherId: teacherId,
        loginUsername: 'mohammad_khaled',
        loginCode: 'B4N8PQ',
      ),
    ]);

    homeworkByStudent[stu1] = StudentHomework(
      id: hw1,
      studentId: stu1,
      surahNumber: 2,
      fromAyah: 1,
      toAyah: 5,
      assignedAt: DateTime.now(),
    );
    lastMemorizationByStudent[stu1] = MemorizationLevel.good;
    lastMemorizationByStudent[stu2] = MemorizationLevel.average;
  }

  Mosque? mosqueById(String id) {
    try {
      return mosques.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<String?> registerMosque({
    required String mosqueName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    final name = mosqueName.trim();
    final mail = email.trim().toLowerCase();
    if (name.isEmpty) return 'أدخل اسم المسجد';
    if (adminName.trim().isEmpty) return 'أدخل اسم المسؤول';
    if (!_looksLikeEmail(mail)) return 'البريد غير صالح';
    if (password.length < 6) return 'كلمة المرور 6 أحرف على الأقل';

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.registerMosque(
          mosqueName: name,
          adminName: adminName.trim(),
          email: mail,
          password: password,
        );
        final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
        final userMap = Map<String, dynamic>.from(data['user'] as Map);
        final mosque = Mosque(
          id: mosqueMap['id'].toString(),
          name: mosqueMap['name'].toString(),
          createdAt: DateTime.tryParse(
                mosqueMap['created_at']?.toString() ?? '',
              ) ??
              DateTime.now(),
        );
        final user = AppUser(
          id: userMap['id'].toString(),
          fullName: userMap['full_name'].toString(),
          role: UserRole.mosqueAdmin,
          mosqueId: mosque.id,
          email: userMap['email']?.toString() ?? mail,
        );
        await _applyAuthSession(
          user: user,
          mosque: mosque,
          admin: _AdminCreds(
            id: user.id,
            fullName: user.fullName,
            email: user.email,
            password: password,
            mosqueId: mosque.id,
          ),
        );
        return null;
      } on ApiException catch (e) {
        return e.message;
      } catch (_) {
        return 'تعذّر الاتصال بالخادم';
      }
    }

    if (mosques.any((m) => m.name == name)) {
      return 'يوجد مسجد بهذا الاسم مسبقًا';
    }
    if (_admins.containsKey(mail)) return 'البريد مستخدم مسبقًا';

    final mosque = Mosque(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    mosques.add(mosque);
    final adminId = _uuid.v4();
    _admins[mail] = _AdminCreds(
      id: adminId,
      fullName: adminName.trim(),
      email: mail,
      password: password,
      mosqueId: mosque.id,
    );
    currentMosque = mosque;
    currentUser = AppUser(
      id: adminId,
      fullName: adminName.trim(),
      role: UserRole.mosqueAdmin,
      mosqueId: mosque.id,
      email: mail,
    );
    await persistLocal();
    return null;
  }

  Future<String?> loginMosqueAdmin({
    required String mosqueName,
    required String phone,
    required String password,
  }) async {
    final name = mosqueName.trim();
    final digits = toWhatsAppDigits(phone.trim(), countryCode: '964');
    String? resolvedEmail;

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.loginMosqueAdmin(
          mosqueName: name,
          phone: digits,
          password: password,
        );
        final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
        final userMap = Map<String, dynamic>.from(data['user'] as Map);
        resolvedEmail = userMap['email']?.toString();
        final mosque = Mosque(
          id: mosqueMap['id'].toString(),
          name: mosqueMap['name'].toString(),
          createdAt: DateTime.tryParse(
                mosqueMap['created_at']?.toString() ?? '',
              ) ??
              DateTime.now(),
        );
        final user = AppUser(
          id: userMap['id'].toString(),
          fullName: userMap['full_name'].toString(),
          role: UserRole.mosqueAdmin,
          mosqueId: mosque.id,
          email: resolvedEmail ?? '',
        );
        await _applyAuthSession(
          user: user,
          mosque: mosque,
          admin: _AdminCreds(
            id: user.id,
            fullName: user.fullName,
            email: user.email,
            password: password,
            mosqueId: mosque.id,
          ),
        );
        return null;
      } on ApiException catch (e) {
        // خطأ مصادقة حقيقي — لا نستخدم الكاش المحلي
        if (e.statusCode == 401 || e.statusCode == 403) return e.message;
        // شبكة/خادم: نحاول الدخول من البيانات المحلية المحفوظة
        final offline = await _tryLocalMosqueAdminLogin(
          name: name,
          mail: resolvedEmail ?? digits,
          password: password,
        );
        if (offline == null) return null;
        return '${e.message} — وجُرّب الدخول المحلي: $offline';
      } catch (_) {
        final offline = await _tryLocalMosqueAdminLogin(
          name: name,
          mail: resolvedEmail ?? digits,
          password: password,
        );
        if (offline == null) return null;
        return 'تعذّر الاتصال بالخادم — ولا توجد جلسة محلية مطابقة';
      }
    }

    return _tryLocalMosqueAdminLogin(
      name: name,
      mail: resolvedEmail ?? digits,
      password: password,
    );
  }

  /// دخول محلي من اللقطة المحفوظة على الجهاز (أوفلاين).
  Future<String?> _tryLocalMosqueAdminLogin({
    required String name,
    required String mail,
    required String password,
  }) async {
    final admin = _admins[mail];
    if (admin == null || admin.password != password) {
      return 'بيانات الدخول غير صحيحة';
    }
    final mosque = mosqueById(admin.mosqueId);
    if (mosque == null || mosque.name != name) {
      return 'اسم المسجد غير مطابق لهذا الحساب';
    }
    currentMosque = mosque;
    currentUser = AppUser(
      id: admin.id,
      fullName: admin.fullName,
      role: UserRole.mosqueAdmin,
      mosqueId: mosque.id,
      email: admin.email,
    );
    await persistLocal();
    return null;
  }

  Future<String?> changeMosqueAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    if (user == null || user.role != UserRole.mosqueAdmin) {
      return 'يلزم تسجيل دخول إدارة المسجد';
    }
    if (newPassword.trim().length < 6) {
      return 'كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل';
    }

    if (SupabaseConfig.isConfigured) {
      try {
        await _api.changeMosqueAdminPassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
      } on ApiException catch (e) {
        return e.message;
      } catch (_) {
        return 'تعذّر الاتصال بالخادم لتغيير كلمة المرور';
      }
    } else {
      final admin = _admins[user.email];
      if (admin == null || admin.password != currentPassword) {
        return 'كلمة المرور الحالية غير صحيحة';
      }
    }

    final mail = user.email;
    final existing = _admins[mail];
    if (existing != null) {
      _admins[mail] = _AdminCreds(
        id: existing.id,
        fullName: existing.fullName,
        email: existing.email,
        password: newPassword,
        mosqueId: existing.mosqueId,
      );
    }
    await persistLocal();
    return null;
  }
  Future<String?> loginTeacher({
    required String fullName,
    required String code,
  }) async {
    final name = fullName.trim();
    final loginCode = code.trim().toUpperCase();

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.loginTeacher(
          fullName: name,
          loginCode: loginCode,
        );
        final teacherMap = Map<String, dynamic>.from(data['teacher'] as Map);
        final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
        final mosque = Mosque(
          id: mosqueMap['id'].toString(),
          name: mosqueMap['name'].toString(),
          createdAt: DateTime.tryParse(
                mosqueMap['created_at']?.toString() ?? '',
              ) ??
              DateTime.now(),
        );
        final teacher = TeacherAccount(
          id: teacherMap['id'].toString(),
          fullName: teacherMap['full_name'].toString(),
          englishName: teacherMap['english_name']?.toString() ?? '',
          englishPrefix: teacherMap['english_prefix']?.toString() ?? '',
          loginCode: teacherMap['login_code'].toString(),
          mosqueId: mosque.id,
        );
        final user = AppUser(
          id: teacher.id,
          fullName: teacher.fullName,
          role: UserRole.teacher,
          mosqueId: mosque.id,
          email: '',
        );
        await _applyAuthSession(user: user, mosque: mosque, teacher: teacher);
        return null;
      } on ApiException catch (e) {
        return e.message;
      } catch (_) {
        return 'تعذّر الاتصال بالخادم';
      }
    }

    TeacherAccount? teacher;
    for (final t in teachers) {
      if (t.fullName == name && t.loginCode.toUpperCase() == loginCode) {
        teacher = t;
        break;
      }
    }
    if (teacher == null) return 'اسم المدرّس أو الرمز غير صحيح';
    currentMosque = mosqueById(teacher.mosqueId);
    currentUser = AppUser(
      id: teacher.id,
      fullName: teacher.fullName,
      role: UserRole.teacher,
      mosqueId: teacher.mosqueId,
      email: '',
    );
    await persistLocal();
    return null;
  }

  Future<String?> loginTeacherPhone({
    required String phone,
    required String password,
  }) async {
    final digits = toWhatsAppDigits(phone.trim(), countryCode: '964');
    if (!SupabaseConfig.isConfigured) {
      return 'يلزم الاتصال بالخادم لدخول المدرّس';
    }
    try {
      final data = await _api.loginTeacherPhone(phone: digits, password: password);
      final teacherMap = Map<String, dynamic>.from(data['teacher'] as Map);
      final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
      final mosque = Mosque(
        id: mosqueMap['id'].toString(),
        name: mosqueMap['name'].toString(),
        createdAt: DateTime.tryParse(
              mosqueMap['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
      );
      final teacher = TeacherAccount(
        id: teacherMap['id'].toString(),
        fullName: teacherMap['full_name'].toString(),
        englishName: teacherMap['english_name']?.toString() ?? '',
        englishPrefix: teacherMap['english_prefix']?.toString() ?? 'XX',
        loginCode: teacherMap['login_code']?.toString() ?? '',
        mosqueId: mosque.id,
      );
      final user = AppUser(
        id: teacher.id,
        fullName: teacher.fullName,
        role: UserRole.teacher,
        mosqueId: mosque.id,
        email: '',
      );
      await _applyAuthSession(user: user, mosque: mosque, teacher: teacher);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر الاتصال بالخادم';
    }
  }

  Future<String?> registerTeacher({
    required String inviteToken,
    required String fullName,
    required String password,
    required String whatsappPhone,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return 'يلزم الاتصال بالخادم لتسجيل المدرّس';
    }
    try {
      final data = await _api.registerTeacher(
        inviteToken: inviteToken,
        fullName: fullName.trim(),
        password: password,
        whatsappPhone: whatsappPhone,
      );
      final teacherMap = Map<String, dynamic>.from(data['teacher'] as Map);
      final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
      final mosque = Mosque(
        id: mosqueMap['id'].toString(),
        name: mosqueMap['name'].toString(),
        createdAt: DateTime.tryParse(
              mosqueMap['created_at']?.toString() ?? '',
            ) ??
            DateTime.now(),
      );
      final teacher = TeacherAccount(
        id: teacherMap['id'].toString(),
        fullName: teacherMap['full_name'].toString(),
        englishName: teacherMap['english_name']?.toString() ?? '',
        englishPrefix: teacherMap['english_prefix']?.toString() ?? 'XX',
        loginCode: teacherMap['login_code']?.toString() ?? '',
        mosqueId: mosque.id,
      );
      final user = AppUser(
        id: teacher.id,
        fullName: teacher.fullName,
        role: UserRole.teacher,
        mosqueId: mosque.id,
        email: '',
      );
      await _applyAuthSession(user: user, mosque: mosque, teacher: teacher);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذّر الاتصال بالخادم';
    }
  }

  Future<({Map<String, dynamic>? invite, String? error})> createTeacherInvite() async {
    if (!SupabaseConfig.isConfigured) {
      return (invite: null, error: 'يلزم الاتصال بالخادم لإنشاء دعوة');
    }
    try {
      final data = await _api.createTeacherInvite();
      final invite = data['invite'];
      if (invite is Map) {
        return (invite: Map<String, dynamic>.from(invite), error: null);
      }
      return (invite: null, error: 'استجابة غير صالحة');
    } on ApiException catch (e) {
      return (invite: null, error: e.message);
    } catch (_) {
      return (invite: null, error: 'تعذّر الاتصال بالخادم');
    }
  }

  Future<String?> loginStudent({
    required String username,
    required String code,
  }) async {
    final userName = username.trim();
    final loginCode = code.trim().toUpperCase();

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.loginStudent(
          username: userName,
          loginCode: loginCode,
        );
        final studentMap = Map<String, dynamic>.from(data['student'] as Map);
        final mosqueMap = Map<String, dynamic>.from(data['mosque'] as Map);
        final mosque = Mosque(
          id: mosqueMap['id'].toString(),
          name: mosqueMap['name'].toString(),
          createdAt: DateTime.tryParse(
                mosqueMap['created_at']?.toString() ?? '',
              ) ??
              DateTime.now(),
        );
        final student = StudentProfile(
          id: studentMap['id'].toString(),
          fullName: studentMap['full_name'].toString(),
          gradeLevel: studentMap['grade_level']?.toString() ?? '',
          age: (studentMap['age'] as num?)?.toInt() ?? 0,
          parentPhone: studentMap['parent_phone']?.toString() ?? '',
          mosqueId: mosque.id,
          teacherId: studentMap['teacher_id'].toString(),
          loginUsername: studentMap['login_username'].toString(),
          loginCode: studentMap['login_code'].toString(),
        );
        final user = AppUser(
          id: student.id,
          fullName: student.fullName,
          role: UserRole.student,
          mosqueId: mosque.id,
          email: '',
        );
        await _applyAuthSession(user: user, mosque: mosque, student: student);
        return null;
      } on ApiException catch (e) {
        return e.message;
      } catch (_) {
        return 'تعذّر الاتصال بالخادم';
      }
    }

    StudentProfile? student;
    for (final s in students) {
      if (s.loginUsername == userName &&
          s.loginCode.toUpperCase() == loginCode) {
        student = s;
        break;
      }
    }
    if (student == null) return 'اسم المستخدم أو الرمز غير صحيح';
    currentMosque = mosqueById(student.mosqueId);
    currentUser = AppUser(
      id: student.id,
      fullName: student.fullName,
      role: UserRole.student,
      mosqueId: student.mosqueId,
      email: '',
    );
    await persistLocal();
    return null;
  }

  void logout() {
    currentUser = null;
    currentMosque = null;
    todaySession = null;
    attendance.clear();
    classSchedule = null;
    sessionHistory.clear();
    attendanceHistory.clear();
    persistLocal();
  }

  List<TeacherAccount> teachersForMosque(String mosqueId) =>
      teachers.where((t) => t.mosqueId == mosqueId).toList();

  List<StudentProfile> studentsForMosque(String mosqueId) =>
      students.where((s) => s.mosqueId == mosqueId).toList();

  List<StudentProfile> studentsForTeacher(String teacherId) =>
      students.where((s) => s.teacherId == teacherId).toList();

  List<StudentProfile> get myStudents {
    final user = currentUser;
    if (user == null || user.role != UserRole.teacher) return const [];
    return studentsForTeacher(user.id);
  }

  /// إنشاء مدرّس وإرجاع الحساب مع الرمز الظاهر مرة واحدة.
  ({TeacherAccount teacher, String? error}) createTeacher({
    required String fullName,
    required String englishName,
  }) {
    final user = currentUser;
    if (user == null || user.role != UserRole.mosqueAdmin) {
      return (teacher: _emptyTeacher(), error: 'صلاحية الإدارة مطلوبة');
    }
    final name = fullName.trim();
    final english = englishName.trim();
    if (name.isEmpty) return (teacher: _emptyTeacher(), error: 'أدخل اسم المدرّس');
    if (english.isEmpty) {
      return (teacher: _emptyTeacher(), error: 'أدخل الاسم بالإنجليزية');
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(english)) {
      return (
        teacher: _emptyTeacher(),
        error: 'الاسم الإنجليزي يجب أن يحتوي أحرفًا لاتينية'
      );
    }
    if (teachers.any(
      (t) => t.mosqueId == user.mosqueId && t.fullName == name,
    )) {
      return (teacher: _emptyTeacher(), error: 'يوجد مدرّس بهذا الاسم');
    }

    final prefix = _codes.englishPrefix(english);
    var code = _codes.teacherCode(english);
    while (teachers.any(
      (t) => t.mosqueId == user.mosqueId && t.loginCode == code,
    )) {
      code = _codes.teacherCode(english);
    }

    final teacher = TeacherAccount(
      id: _uuid.v4(),
      fullName: name,
      englishName: english,
      englishPrefix: prefix,
      loginCode: code,
      mosqueId: user.mosqueId,
    );
    teachers.add(teacher);
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_teacher',
        payload: {
          'id': teacher.id,
          'mosque_id': teacher.mosqueId,
          'full_name': teacher.fullName,
          'english_name': teacher.englishName,
          'english_prefix': teacher.englishPrefix,
          'login_code': teacher.loginCode,
        },
      ),
    );
    return (teacher: teacher, error: null);
  }

  TeacherAccount _emptyTeacher() => TeacherAccount(
        id: '',
        fullName: '',
        englishName: '',
        englishPrefix: 'XX',
        loginCode: '',
        mosqueId: '',
      );

  void deleteTeacher(String id) {
    teachers.removeWhere((t) => t.id == id);
    final studentIds =
        students.where((s) => s.teacherId == id).map((s) => s.id).toSet();
    students.removeWhere((s) => s.teacherId == id);
    attendance.removeWhere((a) => studentIds.contains(a.studentId));
    homeworkByStudent.removeWhere((k, _) => studentIds.contains(k));
    lastMemorizationByStudent.removeWhere((k, _) => studentIds.contains(k));
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'delete_teacher',
        payload: {'id': id},
      ),
    );
  }

  /// تحديث اسم المدرّس دون تغيير رمز الدخول.
  String? updateTeacher({
    required String teacherId,
    required String fullName,
    required String englishName,
  }) {
    final user = currentUser;
    if (user == null || user.role != UserRole.mosqueAdmin) {
      return 'صلاحية الإدارة مطلوبة';
    }
    final i = teachers.indexWhere((t) => t.id == teacherId);
    if (i < 0) return 'المدرّس غير موجود';
    final existing = teachers[i];
    if (existing.mosqueId != user.mosqueId) return 'المدرّس خارج هذا المسجد';

    final name = fullName.trim();
    final english = englishName.trim();
    if (name.isEmpty) return 'أدخل اسم المدرّس';
    if (english.isEmpty) return 'أدخل الاسم بالإنجليزية';
    if (!RegExp(r'[A-Za-z]').hasMatch(english)) {
      return 'الاسم الإنجليزي يجب أن يحتوي أحرفًا لاتينية';
    }
    if (teachers.any(
      (t) =>
          t.mosqueId == user.mosqueId &&
          t.fullName == name &&
          t.id != teacherId,
    )) {
      return 'يوجد مدرّس بهذا الاسم';
    }

    teachers[i] = TeacherAccount(
      id: existing.id,
      fullName: name,
      englishName: english,
      englishPrefix: _codes.englishPrefix(english),
      loginCode: existing.loginCode,
      mosqueId: existing.mosqueId,
    );
    final updated = teachers[i];
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_teacher',
        payload: {
          'id': updated.id,
          'mosque_id': updated.mosqueId,
          'full_name': updated.fullName,
          'english_name': updated.englishName,
          'english_prefix': updated.englishPrefix,
          'login_code': updated.loginCode,
        },
      ),
    );
    return null;
  }

  Future<({StudentProfile student, String? error})> createStudentWithCredentials({
    required String fullName,
    required String gradeLevel,
    required int age,
    required String parentPhone,
  }) async {
    final user = currentUser;
    if (user == null || user.role != UserRole.teacher) {
      return (student: _emptyStudent(), error: 'صلاحية المدرّس مطلوبة');
    }
    final name = fullName.trim();
    if (name.isEmpty) return (student: _emptyStudent(), error: 'أدخل الاسم');
    if (gradeLevel.trim().isEmpty) {
      return (student: _emptyStudent(), error: 'أدخل المرحلة');
    }
    if (age < 4 || age > 25) {
      return (student: _emptyStudent(), error: 'العمر بين 4 و 25');
    }
    if (parentPhone.trim().length < 8) {
      return (student: _emptyStudent(), error: 'رقم ولي الأمر غير صالح');
    }

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.createStudent(
          mosqueId: user.mosqueId,
          teacherId: user.id,
          fullName: name,
          gradeLevel: gradeLevel.trim(),
          age: age,
          parentPhone: parentPhone.trim(),
        );
        final map = Map<String, dynamic>.from(data['student'] as Map);
        final student = StudentProfile(
          id: map['id'].toString(),
          fullName: map['full_name'].toString(),
          gradeLevel: map['grade_level']?.toString() ?? gradeLevel.trim(),
          age: (map['age'] as num?)?.toInt() ?? age,
          parentPhone: map['parent_phone']?.toString() ?? parentPhone.trim(),
          mosqueId: map['mosque_id']?.toString() ?? user.mosqueId,
          teacherId: map['teacher_id']?.toString() ?? user.id,
          loginUsername: map['login_username'].toString(),
          loginCode: map['login_code'].toString(),
        );
        students.removeWhere((s) => s.id == student.id);
        students.add(student);
        _syncAttendanceRoster();
        await persistLocal();
        return (student: student, error: null);
      } on ApiException catch (e) {
        return (student: _emptyStudent(), error: e.message);
      } catch (_) {
        return (
          student: _emptyStudent(),
          error: 'تعذّر حفظ الطالب على الخادم',
        );
      }
    }

    final taken = students
        .where((s) => s.mosqueId == user.mosqueId)
        .map((s) => s.loginUsername.toLowerCase())
        .toSet();
    final username = _codes.studentUsername(name, taken: taken);
    final code = _codes.studentCode();

    final student = StudentProfile(
      id: _uuid.v4(),
      fullName: name,
      gradeLevel: gradeLevel.trim(),
      age: age,
      parentPhone: parentPhone.trim(),
      mosqueId: user.mosqueId,
      teacherId: user.id,
      loginUsername: username,
      loginCode: code,
    );
    students.add(student);
    _syncAttendanceRoster();
    await persistLocal();
    return (student: student, error: null);
  }

  StudentProfile _emptyStudent() => const StudentProfile(
        id: '',
        fullName: '',
        gradeLevel: '',
        age: 0,
        parentPhone: '',
        mosqueId: '',
        teacherId: '',
        loginUsername: '',
        loginCode: '',
      );

  void updateStudent(StudentProfile updated) {
    final i = students.indexWhere((s) => s.id == updated.id);
    if (i < 0) return;
    students[i] = updated;
    _syncAttendanceRoster();
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_student',
        payload: {
          'id': updated.id,
          'mosque_id': updated.mosqueId,
          'teacher_id': updated.teacherId,
          'full_name': updated.fullName,
          'grade_level': updated.gradeLevel,
          'age': updated.age,
          'parent_phone': updated.parentPhone,
          'login_username': updated.loginUsername,
          'login_code': updated.loginCode,
        },
      ),
    );
  }

  String? regenerateStudentCode(String studentId) {
    final i = students.indexWhere((s) => s.id == studentId);
    if (i < 0) return null;
    final code = _codes.studentCode();
    students[i] = students[i].copyWith(loginCode: code);
    final s = students[i];
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_student',
        payload: {
          'id': s.id,
          'mosque_id': s.mosqueId,
          'teacher_id': s.teacherId,
          'full_name': s.fullName,
          'grade_level': s.gradeLevel,
          'age': s.age,
          'parent_phone': s.parentPhone,
          'login_username': s.loginUsername,
          'login_code': s.loginCode,
        },
      ),
    );
    return code;
  }

  void deleteStudent(String id) {
    students.removeWhere((s) => s.id == id);
    attendance.removeWhere((a) => a.studentId == id);
    homeworkByStudent.remove(id);
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'delete_student',
        payload: {'id': id},
      ),
    );
  }

  TeacherAccount? teacherById(String id) {
    try {
      return teachers.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  MemorizationLevel? latestMemorizationFor(String studentId) =>
      lastMemorizationByStudent[studentId];

  Map<MemorizationLevel, int> memorizationOverviewForStudents(
    Iterable<StudentProfile> roster,
  ) {
    final counts = {for (final l in MemorizationLevel.values) l: 0};
    for (final s in roster) {
      final level =
          lastMemorizationByStudent[s.id] ?? MemorizationLevel.notMemorized;
      counts[level] = (counts[level] ?? 0) + 1;
    }
    return counts;
  }

  Map<MemorizationLevel, int> memorizationOverviewForMosque(String mosqueId) =>
      memorizationOverviewForStudents(studentsForMosque(mosqueId));

  Map<MemorizationLevel, int> memorizationOverviewForTeacher(
    String teacherId,
  ) =>
      memorizationOverviewForStudents(studentsForTeacher(teacherId));

  bool get _sessionLocked => todaySession?.isCompleted ?? false;

  Map<String, dynamic> _attendancePayload(AttendanceRecord a) => {
        'id': a.id,
        'session_id': a.sessionId,
        'student_id': a.studentId,
        'status': attendanceStatusWire(a.status),
        'memorization_level': a.memorizationLevel == null
            ? null
            : memorizationWire(a.memorizationLevel!),
        'behavior_score': a.behaviorScore,
        if (a.evaluationConfirmedAt != null)
          'evaluation_confirmed_at':
              a.evaluationConfirmedAt!.toIso8601String(),
      };

  void _syncAttendanceRoster() {
    if (todaySession == null) return;
    final roster = myStudents;
    final existing = {for (final a in attendance) a.studentId: a};
    attendance
      ..clear()
      ..addAll(
        roster.map((s) {
          final prev = existing[s.id];
          if (prev != null) {
            return AttendanceRecord(
              id: prev.id,
              sessionId: todaySession!.id,
              studentId: s.id,
              studentName: s.fullName,
              status: prev.status,
              memorizationLevel: prev.memorizationLevel,
              behaviorScore: prev.behaviorScore,
              evaluationConfirmedAt: prev.evaluationConfirmedAt,
            );
          }
          return AttendanceRecord(
            id: _uuid.v4(),
            sessionId: todaySession!.id,
            studentId: s.id,
            studentName: s.fullName,
            status: AttendanceStatus.unmarked,
          );
        }),
      );
  }

  /// يحفظ مواعيد دروس المدرّس الأسبوعية ويضعها في طابور المزامنة.
  TeacherClassSchedule saveClassSchedule({
    required int lecturesPerWeek,
    required List<int> weekdays,
  }) {
    final user = currentUser;
    if (user == null || user.role != UserRole.teacher) {
      throw StateError('صلاحية المدرّس مطلوبة');
    }
    final days = [...{...weekdays.where((d) => d >= 1 && d <= 7)}]..sort();
    if (lecturesPerWeek < 1 || lecturesPerWeek > 7) {
      throw ArgumentError('عدد المحاضرات بين 1 و 7');
    }
    if (days.length != lecturesPerWeek) {
      throw ArgumentError('اختر أيامًا بعدد المحاضرات الأسبوعية');
    }
    classSchedule = TeacherClassSchedule(
      id: classSchedule?.id ?? _uuid.v4(),
      mosqueId: user.mosqueId,
      teacherId: user.id,
      lecturesPerWeek: lecturesPerWeek,
      weekdays: days,
      active: true,
    );
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_teacher_schedule',
        payload: {
          'id': classSchedule!.id,
          'mosque_id': classSchedule!.mosqueId,
          'teacher_id': classSchedule!.teacherId,
          'lectures_per_week': classSchedule!.lecturesPerWeek,
          'weekdays': classSchedule!.weekdays,
          'active': true,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ),
    );
    return classSchedule!;
  }

  bool get isTodayLectureDay {
    final schedule = classSchedule;
    if (schedule == null || !schedule.active) return false;
    return schedule.isLectureDay(DateTime.now());
  }

  List<DateTime> upcomingLectureDates({int count = 4}) {
    final schedule = classSchedule;
    if (schedule == null || !schedule.active || schedule.weekdays.isEmpty) {
      return const [];
    }
    final out = <DateTime>[];
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    for (var i = 0; i < 60 && out.length < count; i++) {
      final day = cursor.add(Duration(days: i));
      if (schedule.isLectureDay(day)) out.add(day);
    }
    return out;
  }

  /// أرشيف دروس ضمن نطاق تاريخ — للمدرّس حلقته، وللطالب سجلّه فقط.
  List<LessonArchiveRow> lessonArchiveForRange({
    required DateTime from,
    required DateTime to,
  }) {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final me = currentUser;
    if (me == null) return const [];

    Iterable<LessonArchiveRow> rows = attendanceHistory.where((r) {
      final d = DateTime(
        r.sessionDate.year,
        r.sessionDate.month,
        r.sessionDate.day,
      );
      return !d.isBefore(fromDay) && !d.isAfter(toDay);
    });

    if (me.role == UserRole.teacher) {
      final myIds = myStudents.map((s) => s.id).toSet();
      rows = rows.where((r) => myIds.contains(r.studentId));
    } else if (me.role == UserRole.student) {
      rows = rows.where((r) => r.studentId == me.id);
    } else {
      return const [];
    }
    return rows.toList();
  }

  Future<void> refreshLessonArchive({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!SupabaseConfig.isConfigured || !_api.hasHafizToken) return;
    final fromStr =
        '${from.year.toString().padLeft(4, '0')}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    final toStr =
        '${to.year.toString().padLeft(4, '0')}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    final data = await _api.fetchLessonArchive(from: fromStr, to: toStr);
    final nameById = <String, String>{
      for (final s in ((data['students'] as List?) ?? const []).whereType<Map>())
        if ((s['id']?.toString() ?? '').isNotEmpty)
          s['id'].toString(): s['full_name']?.toString() ?? '',
    };
    final sessionDateById = <String, DateTime>{};
    for (final raw in ((data['sessions'] as List?) ?? const []).whereType<Map>()) {
      final id = raw['id']?.toString() ?? '';
      final date = DateTime.tryParse(raw['session_date']?.toString() ?? '');
      if (id.isEmpty || date == null) continue;
      sessionDateById[id] = DateTime(date.year, date.month, date.day);
    }

    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    attendanceHistory.removeWhere((r) {
      final d = DateTime(
        r.sessionDate.year,
        r.sessionDate.month,
        r.sessionDate.day,
      );
      return !d.isBefore(fromDay) && !d.isAfter(toDay);
    });

    for (final raw
        in ((data['attendance'] as List?) ?? const []).whereType<Map>()) {
      final a = Map<String, dynamic>.from(raw);
      final sid = a['student_id']?.toString() ?? '';
      final sessionId = a['session_id']?.toString() ?? '';
      final date = sessionDateById[sessionId];
      if (sid.isEmpty || sessionId.isEmpty || date == null) continue;
      final wire = a['memorization_level']?.toString();
      attendanceHistory.add(
        LessonArchiveRow(
          sessionId: sessionId,
          sessionDate: date,
          studentId: sid,
          studentName: nameById[sid] ?? _studentNameById(sid),
          status: attendanceStatusFromWire(a['status']?.toString()),
          memorizationLevel:
              wire == null || wire.isEmpty ? null : memorizationFromWire(wire),
          behaviorScore: int.tryParse(a['behavior_score']?.toString() ?? ''),
        ),
      );
    }
    attendanceHistory.sort((a, b) {
      final byDate = b.sessionDate.compareTo(a.sessionDate);
      if (byDate != 0) return byDate;
      return a.studentName.compareTo(b.studentName);
    });
    await persistLocal();
  }

  ClassSession startTodaySession() {
    final user = currentUser!;
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);

    if (todaySession != null &&
        todaySession!.teacherId == user.id &&
        todaySession!.sessionDate.year == dateOnly.year &&
        todaySession!.sessionDate.month == dateOnly.month &&
        todaySession!.sessionDate.day == dateOnly.day) {
      _syncAttendanceRoster();
      persistLocal();
      return todaySession!;
    }

    todaySession = ClassSession(
      id: _uuid.v4(),
      mosqueId: user.mosqueId,
      teacherId: user.id,
      sessionDate: dateOnly,
      status: SessionStatus.active,
      startedAt: DateTime.now(),
    );
    _syncAttendanceRoster();
    _enqueue('upsert_session', {
      'id': todaySession!.id,
      'mosque_id': todaySession!.mosqueId,
      'teacher_id': todaySession!.teacherId,
      'session_date':
          '${dateOnly.year.toString().padLeft(4, '0')}-${dateOnly.month.toString().padLeft(2, '0')}-${dateOnly.day.toString().padLeft(2, '0')}',
      'status': 'active',
      'started_at': todaySession!.startedAt.toIso8601String(),
    });
    for (final a in attendance) {
      _enqueue('upsert_attendance', {
        'id': a.id,
        'session_id': a.sessionId,
        'student_id': a.studentId,
        'status': attendanceStatusWire(a.status),
        'memorization_level': a.memorizationLevel == null
            ? null
            : memorizationWire(a.memorizationLevel!),
        'behavior_score': a.behaviorScore,
      });
    }
    _afterWrite();
    return todaySession!;
  }

  ClassSession? endTodaySession() {
    final session = todaySession;
    if (session == null || session.isCompleted) return session;
    final ended = DateTime.now();
    todaySession = ClassSession(
      id: session.id,
      mosqueId: session.mosqueId,
      teacherId: session.teacherId,
      sessionDate: session.sessionDate,
      status: SessionStatus.completed,
      startedAt: session.startedAt,
      endedAt: ended,
    );
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_session',
        payload: {
          'id': todaySession!.id,
          'mosque_id': todaySession!.mosqueId,
          'teacher_id': todaySession!.teacherId,
          'session_date':
              '${session.sessionDate.year.toString().padLeft(4, '0')}-${session.sessionDate.month.toString().padLeft(2, '0')}-${session.sessionDate.day.toString().padLeft(2, '0')}',
          'status': 'completed',
          'started_at': todaySession!.startedAt.toIso8601String(),
          'ended_at': ended.toIso8601String(),
        },
      ),
    );
    return todaySession;
  }

  void setAttendance(String studentId, AttendanceStatus status) {
    if (_sessionLocked) return;
    final index = attendance.indexWhere((a) => a.studentId == studentId);
    if (index >= 0) {
      attendance[index] = attendance[index].copyWith(status: status);
      final a = attendance[index];
      _afterWrite(
        op: SyncOp(
          id: _uuid.v4(),
          type: 'upsert_attendance',
          payload: _attendancePayload(a),
        ),
      );
    }
  }

  void setMemorizationLevel(String studentId, MemorizationLevel level) {
    if (_sessionLocked) return;
    final index = attendance.indexWhere((a) => a.studentId == studentId);
    if (index < 0) return;
    final row = attendance[index];
    if (!row.isAttending) return;
    attendance[index] = row.copyWith(memorizationLevel: level);
    lastMemorizationByStudent[studentId] = level;
    final a = attendance[index];
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_attendance',
        payload: _attendancePayload(a),
      ),
    );
  }

  void setBehaviorScore(String studentId, int score) {
    if (_sessionLocked) return;
    final index = attendance.indexWhere((a) => a.studentId == studentId);
    if (index < 0) return;
    final row = attendance[index];
    if (!row.isAttending) return;
    attendance[index] = row.copyWith(behaviorScore: score.clamp(0, 10));
    final a = attendance[index];
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_attendance',
        payload: _attendancePayload(a),
      ),
    );
  }

  void confirmEvaluation(String studentId) {
    if (_sessionLocked) return;
    final index = attendance.indexWhere((a) => a.studentId == studentId);
    if (index < 0) return;
    final row = attendance[index];
    if (!row.isAttending || row.evaluationConfirmed) return;
    final confirmedAt = DateTime.now();
    attendance[index] =
        row.copyWith(evaluationConfirmedAt: confirmedAt);
    final a = attendance[index];
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_attendance',
        payload: _attendancePayload(a),
      ),
    );
  }

  StudentHomework setStudentHomework({
    required String studentId,
    required int surahNumber,
    required int fromAyah,
    required int toAyah,
    String note = '',
  }) {
    if (_sessionLocked) {
      return homeworkByStudent[studentId] ??
          StudentHomework(
            id: '',
            studentId: studentId,
            surahNumber: surahNumber,
            fromAyah: fromAyah,
            toAyah: toAyah,
            note: note,
            assignedAt: DateTime.now(),
          );
    }
    final previous = homeworkByStudent[studentId];
    if (previous != null) {
      final archived = HomeworkAssignment(
        id: previous.id,
        studentId: studentId,
        sessionId: todaySession?.id,
        surahNumber: previous.surahNumber,
        fromAyah: previous.fromAyah,
        toAyah: previous.toAyah,
        note: previous.note,
        assignedAt: previous.assignedAt,
      );
      homeworkAssignments.removeWhere((a) => a.id == archived.id);
      homeworkAssignments.add(archived);
      _enqueue('upsert_homework_assignment', {
        'id': archived.id,
        'student_id': archived.studentId,
        'session_id': archived.sessionId,
        'surah_number': archived.surahNumber,
        'from_ayah': archived.fromAyah,
        'to_ayah': archived.toAyah,
        'note': archived.note,
        'assigned_at': archived.assignedAt.toIso8601String(),
      });
    }
    final hw = StudentHomework(
      id: _uuid.v4(),
      studentId: studentId,
      surahNumber: surahNumber,
      fromAyah: fromAyah,
      toAyah: toAyah,
      note: note,
      assignedAt: DateTime.now(),
    );
    homeworkByStudent[studentId] = hw;
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_homework',
        payload: {
          'id': hw.id,
          'student_id': hw.studentId,
          'surah_number': hw.surahNumber,
          'from_ayah': hw.fromAyah,
          'to_ayah': hw.toAyah,
          'note': hw.note,
          'assigned_at': hw.assignedAt.toIso8601String(),
        },
      ),
    );
    return hw;
  }

  StudentHomework? homeworkFor(String studentId) =>
      homeworkByStudent[studentId];

  HomeworkAssignment? previousHomeworkFor(String studentId) {
    final current = homeworkByStudent[studentId];
    final candidates = homeworkAssignments
        .where((a) => a.studentId == studentId)
        .where((a) => current == null || a.id != current.id)
        .toList()
      ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  StudentHomework? homeworkForCurrentStudent() {
    final user = currentUser;
    if (user == null || user.role != UserRole.student) return null;
    return homeworkByStudent[user.id];
  }

  void saveProgress(int surahNumber, int ayahNumber) {
    final user = currentUser;
    if (user == null) return;
    progressByStudent[user.id] = ReadingProgress(
      studentId: user.id,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
    );
    _afterWrite(
      op: SyncOp(
        id: _uuid.v4(),
        type: 'upsert_progress',
        payload: {
          'student_id': user.id,
          'surah_number': surahNumber,
          'ayah_number': ayahNumber,
        },
      ),
    );
  }

  ReadingProgress? progressForCurrent() {
    final user = currentUser;
    if (user == null) return null;
    return progressByStudent[user.id];
  }

  bool _looksLikeEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }
}

class _AdminCreds {
  const _AdminCreds({
    required this.id,
    required this.fullName,
    required this.email,
    required this.password,
    required this.mosqueId,
  });

  final String id;
  final String fullName;
  final String email;
  final String password;
  final String mosqueId;
}

final demoRepositoryProvider = Provider<DemoHafizRepository>((ref) {
  throw StateError(
    'DemoHafizRepository must be overridden after restore() in main()',
  );
});

class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => ref.read(demoRepositoryProvider).currentUser;

  Future<String?> registerMosque({
    required String mosqueName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    final err = await ref.read(demoRepositoryProvider).registerMosque(
          mosqueName: mosqueName,
          adminName: adminName,
          email: email,
          password: password,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(teachersControllerProvider);
      ref.invalidate(studentsControllerProvider);
    }
    return err;
  }

  Future<String?> loginMosqueAdmin({
    required String mosqueName,
    required String phone,
    required String password,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginMosqueAdmin(
          mosqueName: mosqueName,
          phone: phone,
          password: password,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(teachersControllerProvider);
      ref.invalidate(studentsControllerProvider);
    }
    return err;
  }

  Future<String?> changeMosqueAdminPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return ref.read(demoRepositoryProvider).changeMosqueAdminPassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
  }

  Future<String?> loginTeacher({
    required String fullName,
    required String code,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginTeacher(
          fullName: fullName,
          code: code,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(studentsControllerProvider);
      ref.invalidate(sessionControllerProvider);
      ref.invalidate(attendanceControllerProvider);
      ref.invalidate(homeworkControllerProvider);
      ref.invalidate(classScheduleControllerProvider);
    }
    return err;
  }

  Future<String?> loginTeacherPhone({
    required String phone,
    required String password,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginTeacherPhone(
          phone: phone,
          password: password,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(studentsControllerProvider);
      ref.invalidate(sessionControllerProvider);
      ref.invalidate(attendanceControllerProvider);
      ref.invalidate(homeworkControllerProvider);
      ref.invalidate(classScheduleControllerProvider);
    }
    return err;
  }

  Future<String?> registerTeacher({
    required String inviteToken,
    required String fullName,
    required String password,
    required String whatsappPhone,
  }) async {
    final err = await ref.read(demoRepositoryProvider).registerTeacher(
          inviteToken: inviteToken,
          fullName: fullName,
          password: password,
          whatsappPhone: whatsappPhone,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(studentsControllerProvider);
      ref.invalidate(sessionControllerProvider);
      ref.invalidate(attendanceControllerProvider);
      ref.invalidate(homeworkControllerProvider);
    }
    return err;
  }

  Future<String?> loginStudent({
    required String username,
    required String code,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginStudent(
          username: username,
          code: code,
        );
    if (err == null) {
      state = ref.read(demoRepositoryProvider).currentUser;
      ref.invalidate(homeworkControllerProvider);
      ref.invalidate(progressControllerProvider);
      ref.invalidate(classScheduleControllerProvider);
    }
    return err;
  }

  void logout() {
    ref.read(demoRepositoryProvider).logout();
    state = null;
    ref.invalidate(sessionControllerProvider);
    ref.invalidate(attendanceControllerProvider);
    ref.invalidate(studentsControllerProvider);
    ref.invalidate(teachersControllerProvider);
    ref.invalidate(homeworkControllerProvider);
    ref.invalidate(classScheduleControllerProvider);
  }
}

class ClassScheduleController extends Notifier<TeacherClassSchedule?> {
  @override
  TeacherClassSchedule? build() =>
      ref.read(demoRepositoryProvider).classSchedule;

  void refresh() {
    state = ref.read(demoRepositoryProvider).classSchedule;
  }

  Future<String?> save({
    required int lecturesPerWeek,
    required List<int> weekdays,
  }) async {
    try {
      state = ref.read(demoRepositoryProvider).saveClassSchedule(
            lecturesPerWeek: lecturesPerWeek,
            weekdays: weekdays,
          );
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Bad state: ', '').replaceFirst(
            'Invalid argument(s): ',
            '',
          );
    }
  }
}

final classScheduleControllerProvider =
    NotifierProvider<ClassScheduleController, TeacherClassSchedule?>(
  ClassScheduleController.new,
);

final authControllerProvider =
    NotifierProvider<AuthController, AppUser?>(AuthController.new);

class SessionController extends Notifier<ClassSession?> {
  @override
  ClassSession? build() => ref.read(demoRepositoryProvider).todaySession;

  void startToday() {
    state = ref.read(demoRepositoryProvider).startTodaySession();
    ref.read(attendanceControllerProvider.notifier).refresh();
  }

  void endToday() {
    state = ref.read(demoRepositoryProvider).endTodaySession();
    ref.read(attendanceControllerProvider.notifier).refresh();
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, ClassSession?>(SessionController.new);

class StudentsController extends Notifier<List<StudentProfile>> {
  @override
  List<StudentProfile> build() {
    final repo = ref.read(demoRepositoryProvider);
    final user = repo.currentUser;
    if (user?.role == UserRole.teacher) {
      return List.unmodifiable(repo.myStudents);
    }
    if (user?.role == UserRole.mosqueAdmin) {
      return List.unmodifiable(repo.studentsForMosque(user!.mosqueId));
    }
    return const [];
  }

  void refresh() {
    state = build();
  }

  Future<({StudentProfile? student, String? error})> add({
    required String fullName,
    required String gradeLevel,
    required int age,
    required String parentPhone,
  }) async {
    final result =
        await ref.read(demoRepositoryProvider).createStudentWithCredentials(
              fullName: fullName,
              gradeLevel: gradeLevel,
              age: age,
              parentPhone: parentPhone,
            );
    if (result.error == null) {
      refresh();
      ref.read(attendanceControllerProvider.notifier).refresh();
    }
    return (
      student: result.error == null ? result.student : null,
      error: result.error,
    );
  }

  void update(StudentProfile student) {
    ref.read(demoRepositoryProvider).updateStudent(student);
    refresh();
    ref.read(attendanceControllerProvider.notifier).refresh();
  }

  String? regenerateCode(String studentId) {
    final code =
        ref.read(demoRepositoryProvider).regenerateStudentCode(studentId);
    refresh();
    return code;
  }

  void remove(String id) {
    ref.read(demoRepositoryProvider).deleteStudent(id);
    refresh();
    ref.read(attendanceControllerProvider.notifier).refresh();
    ref.read(homeworkControllerProvider.notifier).refresh();
  }
}

final studentsControllerProvider =
    NotifierProvider<StudentsController, List<StudentProfile>>(
  StudentsController.new,
);

class TeachersController extends Notifier<List<TeacherAccount>> {
  @override
  List<TeacherAccount> build() {
    final repo = ref.read(demoRepositoryProvider);
    final user = repo.currentUser;
    if (user?.role != UserRole.mosqueAdmin) return const [];
    return List.unmodifiable(repo.teachersForMosque(user!.mosqueId));
  }

  void refresh() => state = build();

  Future<({Map<String, dynamic>? invite, String? error})> createInvite() async {
    return ref.read(demoRepositoryProvider).createTeacherInvite();
  }

  ({TeacherAccount? teacher, String? error}) add({
    required String fullName,
    required String englishName,
  }) {
    final result = ref.read(demoRepositoryProvider).createTeacher(
          fullName: fullName,
          englishName: englishName,
        );
    if (result.error == null) refresh();
    return (
      teacher: result.error == null ? result.teacher : null,
      error: result.error,
    );
  }

  void remove(String id) {
    ref.read(demoRepositoryProvider).deleteTeacher(id);
    refresh();
    ref.read(studentsControllerProvider.notifier).refresh();
  }

  String? update({
    required String teacherId,
    required String fullName,
    required String englishName,
  }) {
    final err = ref.read(demoRepositoryProvider).updateTeacher(
          teacherId: teacherId,
          fullName: fullName,
          englishName: englishName,
        );
    if (err == null) refresh();
    return err;
  }
}

final teachersControllerProvider =
    NotifierProvider<TeachersController, List<TeacherAccount>>(
  TeachersController.new,
);

class AttendanceController extends Notifier<List<AttendanceRecord>> {
  @override
  List<AttendanceRecord> build() {
    return List.unmodifiable(ref.read(demoRepositoryProvider).attendance);
  }

  void refresh() {
    state = List.unmodifiable(ref.read(demoRepositoryProvider).attendance);
  }

  void mark(String studentId, AttendanceStatus status) {
    ref.read(demoRepositoryProvider).setAttendance(studentId, status);
    refresh();
  }

  void setMemorization(String studentId, MemorizationLevel level) {
    ref.read(demoRepositoryProvider).setMemorizationLevel(studentId, level);
    refresh();
  }

  void setBehavior(String studentId, int score) {
    ref.read(demoRepositoryProvider).setBehaviorScore(studentId, score);
    refresh();
  }

  void confirmEvaluation(String studentId) {
    ref.read(demoRepositoryProvider).confirmEvaluation(studentId);
    refresh();
  }
}

final attendanceControllerProvider =
    NotifierProvider<AttendanceController, List<AttendanceRecord>>(
  AttendanceController.new,
);

class HomeworkController extends Notifier<Map<String, StudentHomework>> {
  @override
  Map<String, StudentHomework> build() {
    return Map.unmodifiable(
      ref.read(demoRepositoryProvider).homeworkByStudent,
    );
  }

  void refresh() {
    state = Map.unmodifiable(
      ref.read(demoRepositoryProvider).homeworkByStudent,
    );
  }

  StudentHomework? forStudent(String studentId) => state[studentId];

  StudentHomework? forCurrentStudent() {
    final user = ref.read(authControllerProvider);
    if (user == null || user.role != UserRole.student) return null;
    return state[user.id];
  }

  void assign({
    required String studentId,
    required int surahNumber,
    required int fromAyah,
    required int toAyah,
    String note = '',
  }) {
    ref.read(demoRepositoryProvider).setStudentHomework(
          studentId: studentId,
          surahNumber: surahNumber,
          fromAyah: fromAyah,
          toAyah: toAyah,
          note: note,
        );
    refresh();
  }
}

final homeworkControllerProvider =
    NotifierProvider<HomeworkController, Map<String, StudentHomework>>(
  HomeworkController.new,
);

class ProgressController extends Notifier<ReadingProgress?> {
  @override
  ReadingProgress? build() =>
      ref.read(demoRepositoryProvider).progressForCurrent();

  void save(int surahNumber, int ayahNumber) {
    ref.read(demoRepositoryProvider).saveProgress(surahNumber, ayahNumber);
    state = ref.read(demoRepositoryProvider).progressForCurrent();
  }
}

final progressControllerProvider =
    NotifierProvider<ProgressController, ReadingProgress?>(
  ProgressController.new,
);
