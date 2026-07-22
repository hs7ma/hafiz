/// إعدادات عميل Supabase (anon/publishable فقط — لا تستخدم service_role هنا).
///
/// الافتراضي: مشروع hafiz على Supabase.
/// تجاوز:
///   --dart-define=SUPABASE_URL=...
///   --dart-define=SUPABASE_ANON_KEY=...
/// تعطيل:
///   --dart-define=SUPABASE_URL= --dart-define=SUPABASE_ANON_KEY=
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qlqzdtphwmoohqgqftuv.supabase.co',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFscXpkdHBod21vb2hxZ3FmdHV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ1NzIwMDcsImV4cCI6MjEwMDE0ODAwN30.3fNguivvv7YSpKqVx5YwoJwWljtwFsYV5EXQHllVbeY',
  );

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static String get functionsBase {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    return '$u/functions/v1/hafiz-api';
  }

  static String get registerPageUrl {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    return '$u/functions/v1/serve-register';
  }
}
