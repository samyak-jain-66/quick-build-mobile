import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth/auth_controller.dart';
import 'core/deeplink/deep_link_service.dart';
import 'core/notifications/push_notifications.dart';
import 'core/router/app_router.dart';
import 'theme/app_theme.dart';

class QuickBuildApp extends ConsumerStatefulWidget {
  const QuickBuildApp({super.key});

  @override
  ConsumerState<QuickBuildApp> createState() => _QuickBuildAppState();
}

class _QuickBuildAppState extends ConsumerState<QuickBuildApp> {
  @override
  void initState() {
    super.initState();
    // Kick off deep-link listening after the first frame so the router is
    // fully wired before we try to push a route onto it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deepLinkServiceProvider).start();
      // Pre-register FCM if a Supabase session was already restored from
      // disk on cold start. Subsequent sign-in/out events go through the
      // listener below.
      final session = ref.read(currentSessionProvider);
      if (session != null) {
        ref.read(pushNotificationsServiceProvider).initForUser(session.user.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // React to sign-in / sign-out: register or revoke the FCM token.
    ref.listen<Session?>(currentSessionProvider, (previous, next) {
      final push = ref.read(pushNotificationsServiceProvider);
      if (next != null && next.user.id != previous?.user.id) {
        push.initForUser(next.user.id);
      } else if (next == null && previous != null) {
        push.unregister();
      }
    });

    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Quick-Build',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
