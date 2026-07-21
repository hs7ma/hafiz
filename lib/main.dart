import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'core/constants/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'data/remote/api_client.dart';
import 'data/repositories/demo_repository.dart';
import 'data/sync/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // صوت التلاوة على Windows عبر media_kit (Android/iOS تستخدم just_audio الأصلي).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  }
  await initializeDateFormatting('ar');

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  final store = LocalStore();
  final api = ApiClient();
  await api.loadPersistedToken();
  // مع الخادم (Supabase افتراضيًا): لا نزرع بيانات محلية وهمية.
  final backendReady = api.isConfigured;
  final repo = DemoHafizRepository(
    store: store,
    api: api,
    seedDemoData: !backendReady,
  );
  await repo.restore();

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWith((ref) => store),
      apiClientProvider.overrideWith((ref) => api),
      demoRepositoryProvider.overrideWith((ref) => repo),
    ],
  );
  await container.read(quranReadyProvider.future);
  if (backendReady) {
    container.read(syncControllerProvider);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const HafizApp(),
    ),
  );
}

class HafizApp extends ConsumerWidget {
  const HafizApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'حافظ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
