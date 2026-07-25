import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'foreground_context.dart';
import 'push_service.dart';

/// يربط سياق الشاشة والمزامنة مع خدمة الإشعارات.
class NotificationScope extends ConsumerStatefulWidget {
  const NotificationScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationScope> createState() => _NotificationScopeState();
}

class _NotificationScopeState extends ConsumerState<NotificationScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(pushServiceProvider).maybeNotifySyncRisk();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _locationOf(context);
    if (location.isNotEmpty) {
      ref.read(pushServiceProvider).updateForegroundContext(
            foregroundContextForPath(location),
          );
    }
    return widget.child;
  }

  String _locationOf(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      return '';
    }
  }
}
