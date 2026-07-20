enum UserRole { mosqueAdmin, teacher, student }

enum AttendanceStatus { unmarked, present, absent, late }

enum SessionStatus { active, completed, cancelled }

/// مستويات تقييم الحفظ (أوضح لحلقات التحفيظ من مقياس /10).
enum MemorizationLevel {
  notMemorized,
  poor,
  average,
  good,
  veryGood,
  excellent,
}

extension MemorizationLevelX on MemorizationLevel {
  String get labelAr => switch (this) {
        MemorizationLevel.notMemorized => 'غير حافظ',
        MemorizationLevel.poor => 'سيء',
        MemorizationLevel.average => 'متوسط',
        MemorizationLevel.good => 'جيد',
        MemorizationLevel.veryGood => 'جيد جدا',
        MemorizationLevel.excellent => 'ممتاز',
      };
}

class Mosque {
  const Mosque({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
}

/// طالب في حلقة مدرّس تحت مسجد.
class StudentProfile {
  const StudentProfile({
    required this.id,
    required this.fullName,
    required this.gradeLevel,
    required this.age,
    required this.parentPhone,
    required this.mosqueId,
    required this.teacherId,
    required this.loginUsername,
    required this.loginCode,
  });

  final String id;
  final String fullName;
  final String gradeLevel;
  final int age;
  final String parentPhone;
  final String mosqueId;
  final String teacherId;
  final String loginUsername;
  final String loginCode;

  StudentProfile copyWith({
    String? fullName,
    String? gradeLevel,
    int? age,
    String? parentPhone,
    String? loginUsername,
    String? loginCode,
  }) {
    return StudentProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      gradeLevel: gradeLevel ?? this.gradeLevel,
      age: age ?? this.age,
      parentPhone: parentPhone ?? this.parentPhone,
      mosqueId: mosqueId,
      teacherId: teacherId,
      loginUsername: loginUsername ?? this.loginUsername,
      loginCode: loginCode ?? this.loginCode,
    );
  }
}

class TeacherAccount {
  const TeacherAccount({
    required this.id,
    required this.fullName,
    required this.englishName,
    required this.englishPrefix,
    required this.loginCode,
    required this.mosqueId,
  });

  final String id;
  final String fullName;
  final String englishName;
  final String englishPrefix;
  final String loginCode;
  final String mosqueId;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.mosqueId,
    this.email = '',
  });

  final String id;
  final String fullName;
  final UserRole role;
  final String mosqueId;
  final String email;
}

class ClassSession {
  const ClassSession({
    required this.id,
    required this.mosqueId,
    required this.teacherId,
    required this.sessionDate,
    required this.status,
    required this.startedAt,
  });

  final String id;
  final String mosqueId;
  final String teacherId;
  final DateTime sessionDate;
  final SessionStatus status;
  final DateTime startedAt;
}

/// صف في جدول الدرس اليومي.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.studentName,
    required this.status,
    this.memorizationLevel,
    this.behaviorScore,
  });

  final String id;
  final String sessionId;
  final String studentId;
  final String studentName;
  final AttendanceStatus status;
  final MemorizationLevel? memorizationLevel;
  final int? behaviorScore;

  bool get isAttending =>
      status == AttendanceStatus.present || status == AttendanceStatus.late;

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    MemorizationLevel? memorizationLevel,
    int? behaviorScore,
    bool clearMemorization = false,
    bool clearBehavior = false,
  }) {
    final nextStatus = status ?? this.status;
    final attending = nextStatus == AttendanceStatus.present ||
        nextStatus == AttendanceStatus.late;
    return AttendanceRecord(
      id: id,
      sessionId: sessionId,
      studentId: studentId,
      studentName: studentName,
      status: nextStatus,
      memorizationLevel: !attending
          ? null
          : clearMemorization
              ? null
              : (memorizationLevel ?? this.memorizationLevel),
      behaviorScore: !attending
          ? null
          : clearBehavior
              ? null
              : (behaviorScore ?? this.behaviorScore),
    );
  }
}

/// واجب حفظ فردي لكل طالب.
class StudentHomework {
  const StudentHomework({
    required this.id,
    required this.studentId,
    required this.surahNumber,
    required this.fromAyah,
    required this.toAyah,
    this.note = '',
    required this.assignedAt,
  });

  final String id;
  final String studentId;
  final int surahNumber;
  final int fromAyah;
  final int toAyah;
  final String note;
  final DateTime assignedAt;
}

class ReadingProgress {
  const ReadingProgress({
    required this.studentId,
    required this.surahNumber,
    required this.ayahNumber,
  });

  final String studentId;
  final int surahNumber;
  final int ayahNumber;
}
