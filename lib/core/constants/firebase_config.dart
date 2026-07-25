import 'package:firebase_core/firebase_core.dart';

/// إعدادات Firebase — طريقتان للتفعيل على Android:
///
/// 1) ضع `android/app/google-services.json` من Firebase Console
///    (مفضّل للإنتاج) ثم ابنِ التطبيق عاديًا.
/// 2) أو مرّر dart-define:
///    `--dart-define=FIREBASE_PROJECT_ID=...`
///    `--dart-define=FIREBASE_API_KEY=...`
///    `--dart-define=FIREBASE_APP_ID=...`
///    `--dart-define=FIREBASE_MESSAGING_SENDER_ID=...`
///
/// على الخادم: سرّ Supabase `FIREBASE_SERVICE_ACCOUNT_JSON`.
class FirebaseConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );

  static bool get isConfigured =>
      projectId.isNotEmpty &&
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty;

  static FirebaseOptions? get options {
    if (!isConfigured) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }
}
