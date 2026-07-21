import 'supabase_config.dart';

/// عنوان خادم Express/Railway — اختياري كاحتياطي فقط.
///
/// المسار المعتمد: [SupabaseConfig] (Edge Functions).
/// تفعيل Railway يدويًا:
///   flutter run --dart-define=API_BASE_URL=https://hafiz.up.railway.app
///   مع تعطيل Supabase: --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// مفعّل إن وُجد Supabase (المفضّل) أو Railway.
  static bool get isConfigured =>
      SupabaseConfig.isConfigured || baseUrl.trim().isNotEmpty;

  static String get normalizedBase {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}
