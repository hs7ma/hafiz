import 'supabase_config.dart';

/// عنوان خادم Node (Railway) — احتياطي أثناء الانتقال إلى Supabase.
///
/// المفضّل: ضبط [SupabaseConfig] عبر:
///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// تجاوز Railway محليًا:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
/// تعطيل المزامنة بالكامل:
///   flutter run --dart-define=API_BASE_URL= --dart-define=SUPABASE_URL=
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hafiz.up.railway.app',
  );

  /// مفعّل إن وُجد Supabase أو Railway.
  static bool get isConfigured =>
      SupabaseConfig.isConfigured || baseUrl.trim().isNotEmpty;

  static String get normalizedBase {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}
