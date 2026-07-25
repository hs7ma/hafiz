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
        MemorizationLevel.poor => 'ضعيف',
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
    this.endedAt,
  });

  final String id;
  final String mosqueId;
  final String teacherId;
  final DateTime sessionDate;
  final SessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isCompleted => status == SessionStatus.completed;
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
    this.evaluationConfirmedAt,
  });

  final String id;
  final String sessionId;
  final String studentId;
  final String studentName;
  final AttendanceStatus status;
  final MemorizationLevel? memorizationLevel;
  final int? behaviorScore;
  final DateTime? evaluationConfirmedAt;

  bool get evaluationConfirmed => evaluationConfirmedAt != null;

  bool get isAttending =>
      status == AttendanceStatus.present || status == AttendanceStatus.late;

  AttendanceRecord copyWith({
    AttendanceStatus? status,
    MemorizationLevel? memorizationLevel,
    int? behaviorScore,
    DateTime? evaluationConfirmedAt,
    bool clearMemorization = false,
    bool clearBehavior = false,
    bool clearEvaluationConfirmed = false,
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
      evaluationConfirmedAt: clearEvaluationConfirmed
          ? null
          : (evaluationConfirmedAt ?? this.evaluationConfirmedAt),
    );
  }
}

/// سجل واجب سابق (أرشيف) لعرض «واجب المحاضرة السابقة».
class HomeworkAssignment {
  const HomeworkAssignment({
    required this.id,
    required this.studentId,
    required this.surahNumber,
    required this.fromAyah,
    required this.toAyah,
    this.sessionId,
    this.note = '',
    required this.assignedAt,
  });

  final String id;
  final String studentId;
  final String? sessionId;
  final int surahNumber;
  final int fromAyah;
  final int toAyah;
  final String note;
  final DateTime assignedAt;
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

/// جدول مواعيد دروس المدرّس الأسبوعية.
/// الأيام وفق [DateTime.weekday]: 1=اثنين … 6=سبت … 7=أحد.
class TeacherClassSchedule {
  const TeacherClassSchedule({
    required this.id,
    required this.mosqueId,
    required this.teacherId,
    required this.lecturesPerWeek,
    required this.weekdays,
    this.active = true,
  });

  final String id;
  final String mosqueId;
  final String teacherId;
  final int lecturesPerWeek;
  final List<int> weekdays;
  final bool active;

  bool isLectureDay(DateTime date) => weekdays.contains(date.weekday);

  TeacherClassSchedule copyWith({
    int? lecturesPerWeek,
    List<int>? weekdays,
    bool? active,
  }) {
    return TeacherClassSchedule(
      id: id,
      mosqueId: mosqueId,
      teacherId: teacherId,
      lecturesPerWeek: lecturesPerWeek ?? this.lecturesPerWeek,
      weekdays: weekdays ?? this.weekdays,
      active: active ?? this.active,
    );
  }
}

/// صف أرشيف درس (جلسة + حضور مرتبط).
class LessonArchiveRow {
  const LessonArchiveRow({
    required this.sessionId,
    required this.sessionDate,
    required this.studentId,
    required this.studentName,
    required this.status,
    this.memorizationLevel,
    this.behaviorScore,
  });

  final String sessionId;
  final DateTime sessionDate;
  final String studentId;
  final String studentName;
  final AttendanceStatus status;
  final MemorizationLevel? memorizationLevel;
  final int? behaviorScore;
}

/// أسماء أيام الأسبوع بالعربية (مفتاح = DateTime.weekday).
const Map<int, String> arabicWeekdayLabels = {
  1: 'الاثنين',
  2: 'الثلاثاء',
  3: 'الأربعاء',
  4: 'الخميس',
  5: 'الجمعة',
  6: 'السبت',
  7: 'الأحد',
};
