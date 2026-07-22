import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/supabase_config.dart';
import '../../core/utils/code_generators.dart';
import '../../core/utils/id_utils.dart';
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
  final Map<String, ReadingProgress> progressByStudent = {};
  final Map<String, MemorizationLevel> lastMemorizationByStudent = {};

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
    if (!SupabaseConfig.isConfigured) return 'Supabase غير مضبوط';
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
      return 'تمت المزامنة مع Supabase بنجاح';
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
          ),
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
    required String email,
    required String password,
  }) async {
    final name = mosqueName.trim();
    final mail = email.trim().toLowerCase();

    if (SupabaseConfig.isConfigured) {
      try {
        final data = await _api.loginMosqueAdmin(
          mosqueName: name,
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
        // خطأ مصادقة حقيقي — لا نستخدم الكاش المحلي
        if (e.statusCode == 401 || e.statusCode == 403) return e.message;
        // شبكة/خادم: نحاول الدخول من البيانات المحلية المحفوظة
        final offline = await _tryLocalMosqueAdminLogin(
          name: name,
          mail: mail,
          password: password,
        );
        if (offline == null) return null;
        return '${e.message} — وجُرّب الدخول المحلي: $offline';
      } catch (_) {
        final offline = await _tryLocalMosqueAdminLogin(
          name: name,
          mail: mail,
          password: password,
        );
        if (offline == null) return null;
        return 'تعذّر الاتصال بالخادم — ولا توجد جلسة محلية مطابقة';
      }
    }

    return _tryLocalMosqueAdminLogin(
      name: name,
      mail: mail,
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
      return 'يلزم تسجيل دخول إدارة الجامع';
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

  Future<String?> loginTeacherEmail({
    required String email,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    if (!SupabaseConfig.isConfigured) {
      return 'يلزم الاتصال بالخادم لدخول المدرّس بالبريد';
    }
    try {
      final data = await _api.loginTeacherEmail(email: mail, password: password);
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
        email: teacherMap['email']?.toString() ?? mail,
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
    required String email,
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
        email: email.trim().toLowerCase(),
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
        email: teacherMap['email']?.toString() ?? email.trim().toLowerCase(),
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

  void setAttendance(String studentId, AttendanceStatus status) {
    final index = attendance.indexWhere((a) => a.studentId == studentId);
    if (index >= 0) {
      attendance[index] = attendance[index].copyWith(status: status);
      final a = attendance[index];
      _afterWrite(
        op: SyncOp(
          id: _uuid.v4(),
          type: 'upsert_attendance',
          payload: {
            'id': a.id,
            'session_id': a.sessionId,
            'student_id': a.studentId,
            'status': attendanceStatusWire(a.status),
            'memorization_level': a.memorizationLevel == null
                ? null
                : memorizationWire(a.memorizationLevel!),
            'behavior_score': a.behaviorScore,
          },
        ),
      );
    }
  }

  void setMemorizationLevel(String studentId, MemorizationLevel level) {
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
        payload: {
          'id': a.id,
          'session_id': a.sessionId,
          'student_id': a.studentId,
          'status': attendanceStatusWire(a.status),
          'memorization_level': memorizationWire(level),
          'behavior_score': a.behaviorScore,
        },
      ),
    );
  }

  void setBehaviorScore(String studentId, int score) {
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
        payload: {
          'id': a.id,
          'session_id': a.sessionId,
          'student_id': a.studentId,
          'status': attendanceStatusWire(a.status),
          'memorization_level': a.memorizationLevel == null
              ? null
              : memorizationWire(a.memorizationLevel!),
          'behavior_score': a.behaviorScore,
        },
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
    required String email,
    required String password,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginMosqueAdmin(
          mosqueName: mosqueName,
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
    }
    return err;
  }

  Future<String?> loginTeacherEmail({
    required String email,
    required String password,
  }) async {
    final err = await ref.read(demoRepositoryProvider).loginTeacherEmail(
          email: email,
          password: password,
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

  Future<String?> registerTeacher({
    required String inviteToken,
    required String fullName,
    required String email,
    required String password,
    required String whatsappPhone,
  }) async {
    final err = await ref.read(demoRepositoryProvider).registerTeacher(
          inviteToken: inviteToken,
          fullName: fullName,
          email: email,
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
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AppUser?>(AuthController.new);

class SessionController extends Notifier<ClassSession?> {
  @override
  ClassSession? build() => ref.read(demoRepositoryProvider).todaySession;

  void startToday() {
    state = ref.read(demoRepositoryProvider).startTodaySession();
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
