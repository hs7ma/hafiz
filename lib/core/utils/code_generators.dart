import 'dart:math';

/// مولّدات رموز الدخول للمدرّسين والطلبة.
class CodeGenerators {
  CodeGenerators([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  /// أحرف/أرقام بدون التباس 0/O و 1/I.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// أول حرفين لاتينيين من الاسم الإنجليزي (A–Z).
  String englishPrefix(String englishName) {
    final letters = englishName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
    if (letters.length >= 2) return letters.substring(0, 2);
    if (letters.length == 1) return '${letters}X';
    return 'XX';
  }

  /// رمز المدرّس: حرفان + 6 أرقام، مثال IB482917.
  String teacherCode(String englishName) {
    final prefix = englishPrefix(englishName);
    final digits = List.generate(6, (_) => _random.nextInt(10)).join();
    return '$prefix$digits';
  }

  /// رمز الطالب: 5–8 رموز عشوائية.
  String studentCode({int? length}) {
    final len = length ?? (5 + _random.nextInt(4)); // 5..8
    return List.generate(
      len,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
  }

  /// اسم مستخدم قصير من الاسم + لاحقة رقمية.
  String studentUsername(String fullName, {required Set<String> taken}) {
    final base = fullName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF_]'), '');
    final root = base.isEmpty ? 'talib' : base;
    var candidate = root;
    var n = 1;
    while (taken.contains(candidate.toLowerCase())) {
      candidate = '${root}_$n';
      n++;
    }
    return candidate;
  }
}
