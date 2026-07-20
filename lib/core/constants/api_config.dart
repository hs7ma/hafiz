/// عنوان خادم Node لتطبيق حافظ.
///
/// الافتراضي: محاكي Android → مضيف الجهاز على المنفذ 3000.
/// هاتف حقيقي: مرّر IP الشبكة المحلية:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
/// تعطيل المزامنة مع الخادم:
///   flutter run --dart-define=API_BASE_URL=
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  static String get normalizedBase {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}
