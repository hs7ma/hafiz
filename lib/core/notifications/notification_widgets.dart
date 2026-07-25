import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../constants/supabase_config.dart';
import '../theme/app_colors.dart';
import '../../data/repositories/demo_repository.dart';
import '../../data/sync/sync_controller.dart';
import 'app_notification.dart';
import 'notification_controller.dart';

/// بانر تحذير المزامنة — يظهر طالما يوجد طابور معلّق أو خطأ.
class SyncWarningBanner extends ConsumerWidget {
  const SyncWarningBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoPending = ref.watch(demoRepositoryProvider).pendingSyncCount;
    final configured = SupabaseConfig.isConfigured;
    final sync = configured ? ref.watch(syncControllerProvider) : null;
    final pending = sync?.pending ?? repoPending;

    if (!configured) {
      return _banner(
        context,
        ref,
        text: 'وضع محلي أوفلاين — تُحفظ البيانات على الجهاز',
        bg: AppColors.softGreen.withValues(alpha: 0.55),
        icon: Icons.phone_android,
        tappable: false,
      );
    }

    if (sync!.phase == SyncPhase.syncing) {
      return _banner(
        context,
        ref,
        text: sync.message,
        bg: AppColors.softGreen.withValues(alpha: 0.55),
        icon: Icons.cloud_sync_outlined,
      );
    }

    if (sync.needsLogin ||
        (sync.phase == SyncPhase.error &&
            sync.message.contains('تسجيل الدخول'))) {
      return _banner(
        context,
        ref,
        text: sync.message.isNotEmpty
            ? '${sync.message}\nاضغط بعد تسجيل الدخول للمزامنة'
            : 'يلزم تسجيل الدخول لمزامنة $pending عملية',
        bg: const Color(0xFFFFE0B2).withValues(alpha: 0.95),
        icon: Icons.lock_outline,
      );
    }

    if (sync.phase == SyncPhase.error) {
      return _banner(
        context,
        ref,
        text: sync.message.isNotEmpty
            ? '${sync.message}\nيوجد $pending عمليات بانتظار المزامنة'
            : 'تعذّرت المزامنة — $pending عمليات بانتظار المزامنة',
        bg: const Color(0xFFFFE0B2).withValues(alpha: 0.95),
        icon: Icons.error_outline,
      );
    }

    if (sync.phase == SyncPhase.offline || pending > 0) {
      final text = pending > 0
          ? 'يوجد $pending عمليات بانتظار المزامنة'
          : (sync.message.isNotEmpty
              ? sync.message
              : 'بدون إنترنت — التغييرات محفوظة محليًا');
      return _banner(
        context,
        ref,
        text: text,
        bg: const Color(0xFFFFE0B2).withValues(alpha: 0.95),
        icon: pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _banner(
    BuildContext context,
    WidgetRef ref, {
    required String text,
    required Color bg,
    required IconData icon,
    bool tappable = true,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: tappable && SupabaseConfig.isConfigured
            ? () => ref
                .read(syncControllerProvider.notifier)
                .flush(reason: 'manual', force: true)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.oliveDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.oliveDark,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationControllerProvider).unread;
    return IconButton(
      tooltip: 'الإشعارات',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  static void navigateForNotification(BuildContext context, AppNotification n) {
    switch (n.type) {
      case 'homework_updated':
        context.go('/student');
      case 'no_attendance_today':
      case 'teacher_joined':
        context.go('/admin');
      case 'mosque_registration_approved':
      case 'mosque_registration_rejected':
        context.go('/register/status');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationControllerProvider);
    final fmt = DateFormat('d/M/y HH:mm', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (state.unread > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationControllerProvider.notifier).markAllRead(),
              child: const Text('قراءة الكل'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(notificationControllerProvider.notifier).refresh(),
        child: state.loading && state.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('لا إشعارات بعد')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final n = state.items[index];
                      return Material(
                        color: n.isUnread
                            ? AppColors.softGreen.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.body),
                              const SizedBox(height: 4),
                              Text(
                                '${n.typeLabelAr} · ${fmt.format(n.createdAt.toLocal())}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.ink.withValues(alpha: 0.55),
                                    ),
                              ),
                            ],
                          ),
                          trailing: n.isUnread
                              ? const Icon(Icons.circle, size: 10)
                              : null,
                          onTap: () async {
                            if (n.isUnread) {
                              await ref
                                  .read(notificationControllerProvider.notifier)
                                  .markRead(n.id);
                            }
                            if (context.mounted) {
                              navigateForNotification(context, n);
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
