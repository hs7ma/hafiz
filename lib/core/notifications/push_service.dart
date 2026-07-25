import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/firebase_config.dart';
import '../constants/supabase_config.dart';
import '../../data/models/models.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';
import 'notification_controller.dart';

const _deviceIdKey = 'hafiz_device_id';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _ensureFirebaseApp();
}

Future<bool> _ensureFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) return true;
  try {
    if (FirebaseConfig.isConfigured) {
      await Firebase.initializeApp(options: FirebaseConfig.options!);
      return true;
    }
    // Android: يعتمد على google-services.json عند غياب dart-define.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Firebase.initializeApp();
      return true;
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  return false;
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class PushService {
  PushService(this._ref);

  final Ref _ref;
  final _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;
  String? _deviceId;
  String? _fcmToken;
  bool _initialized = false;
  String _foregroundContext = '';
  String? _registrationPhone;

  bool get hasRealFcmToken =>
      _fcmToken != null &&
      _fcmToken!.isNotEmpty &&
      !_fcmToken!.startsWith('local:');

  Future<void> initialize() async {
    if (_initialized || !SupabaseConfig.isConfigured) return;
    _initialized = true;

    await _ensureDeviceId();
    await _initLocalNotifications();

    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final ready = await _ensureFirebaseApp();
    if (!ready) {
      debugPrint('FCM skipped: Firebase not configured (google-services.json or dart-define)');
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      _fcmToken = await messaging.getToken();
      if (hasRealFcmToken) {
        unawaited(_syncDeviceToken());
      } else {
        debugPrint('FCM token unavailable — device not registered for Push');
      }
      _tokenSub = messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        unawaited(_syncDeviceToken());
      });
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        _ref.read(notificationControllerProvider.notifier).refresh();
        final ctx = message.data['foreground_context']?.toString() ?? '';
        if (ctx.isNotEmpty && ctx == _foregroundContext) {
          return;
        }
        final title = message.notification?.title ?? 'حافظ';
        final body = message.notification?.body ?? '';
        if (title.isEmpty && body.isEmpty) return;
        _showLocal(title: title, body: body);
      });
    } catch (e) {
      debugPrint('FCM init skipped: $e');
    }

    _ref.listen(authControllerProvider, (prev, next) {
      if (next != null) {
        unawaited(_syncDeviceToken());
      } else if (prev != null) {
        unawaited(_unregisterFor(prev));
      }
    });
  }

  Future<void> _ensureDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _local.initialize(init);
  }

  void updateForegroundContext(String context) {
    if (_foregroundContext == context) return;
    _foregroundContext = context;
    unawaited(_syncDeviceToken());
  }

  void bindRegistrationPhone(String? phoneDigits) {
    _registrationPhone = phoneDigits;
    unawaited(_syncDeviceToken());
  }

  Future<void> _syncDeviceToken() async {
    if (!SupabaseConfig.isConfigured || _deviceId == null) return;
    // لا نسجّل placeholder — Push يحتاج توكن FCM حقيقي فقط.
    if (!hasRealFcmToken) return;

    final api = _ref.read(apiClientProvider);
    final user = _ref.read(authControllerProvider);

    try {
      if (user != null) {
        await api.registerDeviceToken(
          fcmToken: _fcmToken!,
          deviceId: _deviceId!,
          foregroundContext:
              _foregroundContext.isEmpty ? null : _foregroundContext,
          recipientType: _recipientType(user.role),
          recipientId: user.id,
          mosqueId: user.mosqueId,
        );
        return;
      }
      if (_registrationPhone != null && _registrationPhone!.isNotEmpty) {
        await api.registerDeviceToken(
          fcmToken: _fcmToken!,
          deviceId: _deviceId!,
          foregroundContext: 'registration_status',
          recipientType: 'registration',
          recipientId: _registrationPhone!,
        );
      }
    } catch (_) {
      /* ignore */
    }
  }

  String _recipientType(UserRole role) => switch (role) {
        UserRole.mosqueAdmin => 'mosque_admin',
        UserRole.teacher => 'teacher',
        UserRole.student => 'student',
      };

  Future<void> _unregisterFor(AppUser user) async {
    if (_deviceId == null) return;
    try {
      await _ref.read(apiClientProvider).unregisterDeviceToken(
            deviceId: _deviceId!,
            recipientType: _recipientType(user.role),
            recipientId: user.id,
          );
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> unregister() async {
    if (_deviceId == null) return;
    try {
      await _ref.read(apiClientProvider).unregisterDeviceToken(
            deviceId: _deviceId!,
            recipientType: _ref.read(authControllerProvider) != null
                ? _recipientType(_ref.read(authControllerProvider)!.role)
                : 'registration',
            recipientId: _ref.read(authControllerProvider)?.id ??
                _registrationPhone ??
                '',
          );
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> maybeNotifySyncRisk() async {
    if (!SupabaseConfig.isConfigured) return;
    final sync = _ref.read(syncControllerProvider);
    final pending = sync.pending;
    if (pending <= 0) return;
    if (sync.phase != SyncPhase.error &&
        sync.phase != SyncPhase.offline &&
        !sync.needsLogin) {
      return;
    }
    await _showLocal(
      title: 'مزامنة معلّقة',
      body: 'يوجد $pending عمليات بانتظار المزامنة',
    );
  }

  Future<void> _showLocal({
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      'hafiz_alerts',
      'تنبيهات حافظ',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: android),
    );
  }

  void dispose() {
    _foregroundSub?.cancel();
    _tokenSub?.cancel();
  }
}
