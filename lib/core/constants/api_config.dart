/// عنوان خادم Node لتطبيق حافظ.
///
/// الافتراضي: خادم الإنتاج على Railway (يعمل على Android / iOS / Windows).
/// تجاوز محلي:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
/// تعطيل المزامنة:
///   flutter run --dart-define=API_BASE_URL=
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hafiz.up.railway.app',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  static String get normalizedBase {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}
