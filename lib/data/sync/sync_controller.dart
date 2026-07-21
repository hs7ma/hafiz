import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/api_config.dart';
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
  });

  final SyncPhase phase;
  final int pending;
  final String message;
  final DateTime? lastSyncedAt;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    String? message,
    DateTime? lastSyncedAt,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      pending: pending ?? this.pending,
      message: message ?? this.message,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class SyncController extends Notifier<SyncStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _flushing = false;

  @override
  SyncStatus build() {
    ref.onDispose(() => _sub?.cancel());
    if (ApiConfig.isConfigured) {
      _sub = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online) {
          unawaited(flush());
        } else {
          state = state.copyWith(
            phase: SyncPhase.offline,
            message: 'بدون اتصال — تُحفظ التغييرات محليًا',
          );
        }
      });
      // محاولة أولية
      Future.microtask(flush);
    }
    return SyncStatus(
      phase: ApiConfig.isConfigured ? SyncPhase.idle : SyncPhase.offline,
      message: ApiConfig.isConfigured
          ? 'جاهز للمزامنة مع Supabase'
          : 'وضع محلي فقط (بدون خادم)',
    );
  }

  Future<void> flush() async {
    if (!ApiConfig.isConfigured || _flushing) return;
    final repo = ref.read(demoRepositoryProvider);
    final pending = repo.pendingSyncCount;
    if (pending == 0) {
      state = state.copyWith(phase: SyncPhase.idle, pending: 0, message: 'لا طابور معلّق');
      return;
    }

    _flushing = true;
    state = state.copyWith(
      phase: SyncPhase.syncing,
      pending: pending,
      message: 'جاري المزامنة ($pending)...',
    );
    try {
      final result = await repo.flushSyncQueue();
      state = state.copyWith(
        phase: SyncPhase.idle,
        pending: repo.pendingSyncCount,
        message: result,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        phase: SyncPhase.error,
        pending: repo.pendingSyncCount,
        message: e.toString(),
      );
    } finally {
      _flushing = false;
    }
  }
}

/// إنشاء معرّف عملية مزامنة.
String newSyncOpId() => const Uuid().v4();
