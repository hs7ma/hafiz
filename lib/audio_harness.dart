// نقطة دخول مؤقتة لاختبار مشغّل التلاوة وحده دون تسجيل دخول.
// تُشغَّل بـ: flutter run -t lib/audio_harness.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/audio/audio_platform.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'data/remote/api_client.dart';
import 'data/repositories/demo_repository.dart';
import 'data/sync/sync_controller.dart';
import 'features/mushaf/mushaf_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAudioPlatform();
  await initializeDateFormatting('ar');

  final store = LocalStore();
  final api = ApiClient();
  final repo = DemoHafizRepository(store: store, api: api, seedDemoData: true);
  await repo.restore();

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWith((ref) => store),
      apiClientProvider.overrideWith((ref) => api),
      demoRepositoryProvider.overrideWith((ref) => repo),
    ],
  );
  await container.read(quranReadyProvider.future);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        title: 'اختبار مشغّل التلاوة',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: MushafScreen(),
        ),
      ),
    ),
  );
}
