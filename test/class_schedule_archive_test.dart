import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hafiz/data/local/local_store.dart';
import 'package:hafiz/data/models/models.dart';
import 'package:hafiz/data/remote/api_client.dart';
import 'package:hafiz/data/repositories/demo_repository.dart';

void main() {
  const mosqueId = 'm-1';
  const teacherA = 't-a';
  const teacherB = 't-b';
  const studentA = 's-a';
  const studentB = 's-b';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    return DemoHafizRepository(
      store: LocalStore(),
      api: ApiClient(client: client),
      seedDemoData: false,
    );
  }

  test('pull merges teacher schedule and upcoming lecture days', () async {
    final repo = buildRepo({
      'mosque': {'id': mosqueId, 'name': 'جامع التقى'},
      'teachers': const [],
      'students': const [],
      'sessions': const [],
      'attendance': const [],
      'student_homework': const [],
      'progress': const [],
      'teacher_class_schedules': [
        {
          'id': 'sch-1',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'lectures_per_week': 3,
          'weekdays': [6, 1, 3],
          'active': true,
        },
      ],
    });
    repo.currentUser = const AppUser(
      id: teacherA,
      fullName: 'الشيخ',
      role: UserRole.teacher,
      mosqueId: mosqueId,
    );

    await repo.pullFromServer(mosqueId);

    expect(repo.classSchedule, isNotNull);
    expect(repo.classSchedule!.lecturesPerWeek, 3);
    expect(repo.classSchedule!.weekdays, [1, 3, 6]);
    expect(repo.upcomingLectureDates(count: 3), isNotEmpty);
  });

  test('teacher archive only includes own students', () async {
    final today = DateTime.now();
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final repo = buildRepo({
      'mosque': {'id': mosqueId, 'name': 'جامع التقى'},
      'teachers': const [],
      'students': [
        {
          'id': studentA,
          'full_name': 'أحمد',
          'grade_level': '5',
          'age': 11,
          'parent_phone': '9647700000001',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'login_username': 'ahmed',
          'login_code': '11111',
        },
        {
          'id': studentB,
          'full_name': 'سارة',
          'grade_level': '5',
          'age': 11,
          'parent_phone': '9647700000002',
          'mosque_id': mosqueId,
          'teacher_id': teacherB,
          'login_username': 'sara',
          'login_code': '22222',
        },
      ],
      'sessions': [
        {
          'id': 'sess-a',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'session_date': date,
          'status': 'active',
          'started_at': today.toIso8601String(),
        },
      ],
      'attendance': [
        {
          'id': 'att-a',
          'session_id': 'sess-a',
          'student_id': studentA,
          'status': 'present',
          'memorization_level': 'good',
        },
        {
          'id': 'att-b',
          'session_id': 'sess-a',
          'student_id': studentB,
          'status': 'present',
          'memorization_level': 'excellent',
        },
      ],
      'student_homework': const [],
      'progress': const [],
      'teacher_class_schedules': const [],
    });
    repo.currentUser = const AppUser(
      id: teacherA,
      fullName: 'الشيخ',
      role: UserRole.teacher,
      mosqueId: mosqueId,
    );

    await repo.pullFromServer(mosqueId);

    final rows = repo.lessonArchiveForRange(
      from: DateTime(today.year, today.month, today.day),
      to: DateTime(today.year, today.month, today.day),
    );
    expect(rows.length, 1);
    expect(rows.single.studentId, studentA);
  });

  test('student archive only sees own attendance rows', () async {
    final today = DateTime.now();
    final date =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final repo = buildRepo({
      'mosque': {'id': mosqueId, 'name': 'جامع التقى'},
      'teachers': const [],
      'students': [
        {
          'id': studentA,
          'full_name': 'أحمد',
          'grade_level': '5',
          'age': 11,
          'parent_phone': '9647700000001',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'login_username': 'ahmed',
          'login_code': '11111',
        },
      ],
      'sessions': [
        {
          'id': 'sess-a',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'session_date': date,
          'status': 'active',
          'started_at': today.toIso8601String(),
        },
      ],
      'attendance': [
        {
          'id': 'att-a',
          'session_id': 'sess-a',
          'student_id': studentA,
          'status': 'present',
          'memorization_level': 'good',
        },
      ],
      'student_homework': const [],
      'progress': const [],
      'teacher_class_schedules': [
        {
          'id': 'sch-1',
          'mosque_id': mosqueId,
          'teacher_id': teacherA,
          'lectures_per_week': 2,
          'weekdays': [6, 1],
          'active': true,
        },
      ],
    });
    repo.currentUser = const AppUser(
      id: studentA,
      fullName: 'أحمد',
      role: UserRole.student,
      mosqueId: mosqueId,
    );
    repo.students.add(
      const StudentProfile(
        id: studentA,
        fullName: 'أحمد',
        gradeLevel: '5',
        age: 11,
        parentPhone: '9647700000001',
        mosqueId: mosqueId,
        teacherId: teacherA,
        loginUsername: 'ahmed',
        loginCode: '11111',
      ),
    );

    await repo.pullFromServer(mosqueId);

    expect(repo.classSchedule?.teacherId, teacherA);
    final rows = repo.lessonArchiveForRange(
      from: DateTime(today.year, today.month, 1),
      to: DateTime(today.year, today.month + 1, 0),
    );
    expect(rows.every((r) => r.studentId == studentA), isTrue);
  });
}
