import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supabase_config.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';
import 'app_notification.dart';

class NotificationState {
  const NotificationState({
    this.items = const [],
    this.unread = 0,
    this.loading = false,
    this.error = '',
  });

  final List<AppNotification> items;
  final int unread;
  final bool loading;
  final String error;

  NotificationState copyWith({
    List<AppNotification>? items,
    int? unread,
    bool? loading,
    String? error,
  }) {
    return NotificationState(
      items: items ?? this.items,
      unread: unread ?? this.unread,
      loading: loading ?? this.loading,
      error: error ?? this.error,
    );
  }
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationState>(
  NotificationController.new,
);

class NotificationController extends Notifier<NotificationState> {
  Timer? _poll;

  @override
  NotificationState build() {
    ref.onDispose(() => _poll?.cancel());
    ref.listen(authControllerProvider, (prev, next) {
      if (next != null) {
        unawaited(refresh());
        _startPolling();
      } else {
        _poll?.cancel();
        state = const NotificationState();
      }
    });
    if (ref.read(authControllerProvider) != null) {
      Future.microtask(refresh);
      _startPolling();
    }
    return const NotificationState();
  }

  void _startPolling() {
    _poll?.cancel();
    if (!SupabaseConfig.isConfigured) return;
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  Future<void> refresh() async {
    if (!SupabaseConfig.isConfigured) return;
    if (ref.read(authControllerProvider) == null) return;
    state = state.copyWith(loading: true, error: '');
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.listNotifications();
      final raw = data['notifications'];
      final list = <AppNotification>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            list.add(AppNotification.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
      state = state.copyWith(
        items: list,
        unread: data['unread'] is int
            ? data['unread'] as int
            : list.where((n) => n.isUnread).length,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> markRead(String id) async {
    try {
      await ref.read(apiClientProvider).markNotificationRead(id);
      state = state.copyWith(
        items: [
          for (final n in state.items)
            if (n.id == id)
              AppNotification(
                id: n.id,
                type: n.type,
                priority: n.priority,
                title: n.title,
                body: n.body,
                createdAt: n.createdAt,
                readAt: DateTime.now(),
                entityRef: n.entityRef,
                mosqueId: n.mosqueId,
              )
            else
              n,
        ],
        unread: state.unread > 0 ? state.unread - 1 : 0,
      );
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> markAllRead() async {
    try {
      await ref.read(apiClientProvider).markAllNotificationsRead();
      await refresh();
    } catch (_) {
      /* ignore */
    }
  }
}
