/// إعدادات الاتصال بمشروع Hafiz على Supabase (anon فقط).
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

  static String get apiBase {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    return '$u/functions/v1/hafiz-api';
  }
}
