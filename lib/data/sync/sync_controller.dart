import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/supabase_config.dart';
import '../local/local_store.dart';
import '../remote/api_client.dart';
import '../repositories/demo_repository.dart';

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

enum SyncPhase { idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.message = '',
    this.lastSyncedAt,
    this.needsLogin = false,
  });

  final SyncPhase phase;
  final int pending;
  final String message;
  final DateTime? lastSyncedAt;
  final bool needsLogin;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    String? message,
    DateTime? lastSyncedAt,
    bool? needsLogin,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      pending: pending ?? this.pending,
      message: message ?? this.message,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      needsLogin: needsLogin ?? this.needsLogin,
    );
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

class SyncController extends Notifier<SyncStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retryTimer;
  _LifecycleObserver? _lifecycle;
  bool _flushing = false;
  int _backoffSeconds = 8;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _sub?.cancel();
      _retryTimer?.cancel();
      final life = _lifecycle;
      if (life != null) {
        WidgetsBinding.instance.removeObserver(life);
      }
    });

    if (SupabaseConfig.isConfigured) {
      _lifecycle = _LifecycleObserver(onResume: () {
        unawaited(flush(reason: 'resume'));
      });
      WidgetsBinding.instance.addObserver(_lifecycle!);

      _sub = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) {
          _backoffSeconds = 8;
          unawaited(flush(reason: 'connectivity'));
        } else {
          final pending = ref.read(demoRepositoryProvider).pendingSyncCount;
          state = state.copyWith(
            phase: SyncPhase.offline,
            pending: pending,
            needsLogin: false,
            message: pending > 0
                ? 'بدون اتصال — $pending عملية محفوظة محليًا'
                : 'بدون اتصال — تُحفظ التغييرات محليًا',
          );
        }
      });

      // إعادة محاولة دورية طالما يوجد طابور معلّق
      _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        final pending = ref.read(demoRepositoryProvider).pendingSyncCount;
        if (pending > 0 && !_flushing) {
          unawaited(flush(reason: 'timer'));
        }
      });

      Future.microtask(() => flush(reason: 'startup'));
    }

    return SyncStatus(
      phase: SupabaseConfig.isConfigured ? SyncPhase.idle : SyncPhase.offline,
      message: SupabaseConfig.isConfigured
          ? 'جاهز للمزامنة مع Supabase'
          : 'وضع محلي فقط (بدون خادم)',
    );
  }

  /// مزامنة يدوية/تلقائية. [force] يتجاوز التباطؤ بعد فشل حديث.
  Future<void> flush({String reason = 'manual', bool force = false}) async {
    if (!SupabaseConfig.isConfigured || _flushing) return;

    final repo = ref.read(demoRepositoryProvider);
    final pending = repo.pendingSyncCount;
    if (pending == 0) {
      _backoffSeconds = 8;
      state = state.copyWith(
        phase: SyncPhase.idle,
        pending: 0,
        needsLogin: false,
        message: 'لا طابور معلّق',
      );
      return;
    }

    // على المحاولات التلقائية: لا نطرق الخادم كل ثانية بعد فشل
    if (!force &&
        reason != 'manual' &&
        reason != 'startup' &&
        reason != 'connectivity' &&
        reason != 'resume' &&
        state.phase == SyncPhase.error &&
        state.lastSyncedAt != null) {
      final waited = DateTime.now().difference(state.lastSyncedAt!);
      if (waited < Duration(seconds: _backoffSeconds)) return;
    }

    _flushing = true;
    state = state.copyWith(
      phase: SyncPhase.syncing,
      pending: pending,
      needsLogin: false,
      message: 'جاري المزامنة ($pending)...',
    );

    try {
      final result = await repo.flushSyncQueue();
      _backoffSeconds = 8;
      state = state.copyWith(
        phase: SyncPhase.idle,
        pending: repo.pendingSyncCount,
        needsLogin: false,
        message: result,
        lastSyncedAt: DateTime.now(),
      );
    } on SyncException catch (e) {
      _backoffSeconds = (_backoffSeconds * 2).clamp(8, 120);
      final left = repo.pendingSyncCount;
      state = state.copyWith(
        phase: e.kind == SyncFailureKind.offline
            ? SyncPhase.offline
            : SyncPhase.error,
        pending: left,
        needsLogin: e.kind == SyncFailureKind.auth,
        message: e.message,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      _backoffSeconds = (_backoffSeconds * 2).clamp(8, 120);
      state = state.copyWith(
        phase: SyncPhase.error,
        pending: repo.pendingSyncCount,
        needsLogin: false,
        message: e.toString().contains('محفوظة')
            ? e.toString().replaceFirst('Exception: ', '')
            : 'تعذّرت المزامنة — البيانات ما زالت محفوظة محليًا',
        lastSyncedAt: DateTime.now(),
      );
    } finally {
      _flushing = false;
    }
  }
}

/// إنشاء معرّف عملية مزامنة.
String newSyncOpId() => const Uuid().v4();
