/// إعدادات عميل Supabase (anon/publishable فقط — لا تستخدم service_role هنا).
///
/// التشغيل:
///   flutter run \\
///     --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co \\
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// إن تُركا فارغين يُستخدم مسار Railway القديم عبر [ApiConfig] إن وُجد.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
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

  static String get platformPageUrl {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    return '$u/functions/v1/serve-platform';
  }
}
