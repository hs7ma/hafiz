import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hafiz/data/local/local_store.dart';
import 'package:hafiz/data/models/models.dart';
import 'package:hafiz/data/remote/api_client.dart';
import 'package:hafiz/data/repositories/demo_repository.dart';

/// جلسة اليوم وحضورها يجب أن تُقرأ من الخادم أيضًا، وإلا لم يرَ جهاز ثانٍ
/// عمل اليوم رغم وجوده في قاعدة البيانات.
void main() {
  const mosqueId = 'm-1';
  const teacherId = 't-1';
  const studentId = 's-1';
  const sessionId = 'sess-1';

  String today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  DemoHafizRepository buildRepo(Map<String, dynamic> pullResponse) {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/sync/pull')) {
        return http.Response(
          jsonEncode(pullResponse),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final repo = DemoHafizRepository(
      store: LocalStore(),
      api: ApiClient(client: client),
      seedDemoData: false,
    );
    repo.currentUser = const AppUser(
      id: teacherId,
      fullName: 'الشيخ إبراهيم',
      role: UserRole.teacher,
      mosqueId: mosqueId,
    );
    repo.students.add(
      const StudentProfile(
        id: studentId,
        fullName: 'أحمد يوسف',
        gradeLevel: 'الخامس',
        age: 11,
        parentPhone: '9647700000000',
        mosqueId: mosqueId,
        teacherId: teacherId,
        loginUsername: 'ahmed',
        loginCode: '12345',
      ),
    );
    return repo;
  }

  Map<String, dynamic> pullPayload({
    String status = 'present',
    String? level = 'good',
    int? behavior = 8,
  }) {
    return {
      'mosque': {'id': mosqueId, 'name': 'جامع التقى'},
      'teachers': const [],
      'students': const [],
      'sessions': [
        {
          'id': sessionId,
          'mosque_id': mosqueId,
          'teacher_id': teacherId,
          'session_date': today(),
          'status': 'active',
          'started_at': DateTime.now().toIso8601String(),
        },
      ],
      'attendance': [
        {
          'id': 'att-1',
          'session_id': sessionId,
          'student_id': studentId,
          'status': status,
          'memorization_level': level,
          'behavior_score': behavior,
        },
      ],
      'student_homework': const [],
      'progress': const [],
    };
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pull adopts today session and attendance from the server', () async {
    final repo = buildRepo(pullPayload());
    await repo.pullFromServer(mosqueId);

    expect(repo.todaySession, isNotNull);
    expect(repo.todaySession!.id, sessionId);
    expect(repo.attendance.length, 1);
    final row = repo.attendance.first;
    expect(row.studentId, studentId);
    expect(row.studentName, 'أحمد يوسف');
    expect(row.status, AttendanceStatus.present);
    expect(row.memorizationLevel, MemorizationLevel.good);
    expect(row.behaviorScore, 8);
    expect(repo.latestMemorizationFor(studentId), MemorizationLevel.good);
  });

  test('unmarked attendance keeps memorization empty', () async {
    final repo = buildRepo(
      pullPayload(status: 'unmarked', level: null, behavior: null),
    );
    await repo.pullFromServer(mosqueId);

    expect(repo.attendance.single.status, AttendanceStatus.unmarked);
    expect(repo.attendance.single.memorizationLevel, isNull);
    expect(repo.latestMemorizationFor(studentId), isNull);
  });

  test('local edit not yet pushed survives a pull', () async {
    final repo = buildRepo(pullPayload());
    await repo.pullFromServer(mosqueId);
    repo.setMemorizationLevel(studentId, MemorizationLevel.excellent);
    expect(repo.pendingSyncCount, greaterThan(0));

    await repo.pullFromServer(mosqueId);

    expect(
      repo.attendance.single.memorizationLevel,
      MemorizationLevel.excellent,
    );
    expect(repo.latestMemorizationFor(studentId), MemorizationLevel.excellent);
  });
}
