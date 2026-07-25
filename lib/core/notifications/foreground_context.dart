/// سياق الشاشة النشطة — يُرسل للخادم لقمع Push المكرر.
///
/// قمع واجب الطالب فقط على شاشة «اليوم» (`/student`)،
/// وليس أثناء المصحف أو التقدّم.
String foregroundContextForPath(String location) {
  final path = location.split('?').first;
  if (path.startsWith('/register/status')) return 'registration_status';
  if (path == '/admin' || path.startsWith('/admin/')) return 'admin_home';
  // شاشة الواجب فقط — باقي مسارات الطالب لا تقمع Push الواجب
  if (path == '/student') return 'student_homework';
  if (path == '/teacher' || path.startsWith('/teacher/')) return 'teacher_home';
  if (path == '/notifications' || path.startsWith('/notifications')) {
    return 'notifications';
  }
  return '';
}
