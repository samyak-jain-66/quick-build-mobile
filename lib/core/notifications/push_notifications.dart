import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/notifications_repository.dart';

/// Top-level entry point Flutter requires for FCM background delivery.
/// The app isolate is not running when this fires; the system itself
/// renders the tray notification, we just keep the entry point so the
/// FCM Android plugin doesn't drop the message.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty - the system handles display via the
  // `notification` block on the message.
}

/// Owns the FCM lifecycle for the signed-in user: requests notification
/// permission, fetches the device token, registers it with the API, and
/// re-registers whenever Firebase rotates the token. Also wires up
/// foreground / tap handlers.
class PushNotificationsService {
  PushNotificationsService(this._ref);

  final Ref _ref;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _registeredForUserId;
  String? _lastToken;

  bool get isInitialized => _registeredForUserId != null;
  String? get currentToken => _lastToken;

  Future<void> initForUser(String userId) async {
    if (_registeredForUserId == userId) return; // already wired
    // Firebase is not initialized on iOS yet (see lib/main.dart). Skip
    // FCM registration there so callers don't trip the
    // "[core/no-app] No Firebase App '[DEFAULT]' has been created" error.
    if (Platform.isIOS) return;
    _registeredForUserId = userId;

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _registeredForUserId = null;
      return;
    }

    // Foreground messages on Android show no system tray banner by
    // default; the data still flows through here for in-app handling.
    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Tap when the app is alive but backgrounded.
    _openedSub?.cancel();
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);

    // Cold-start tap (app launched from a notification).
    final initial = await messaging.getInitialMessage();
    if (initial != null) _onMessageTap(initial);

    // Token: Android often returns null on the first call before Play
    // services have finished registering, so we also listen on
    // onTokenRefresh which fires once the token is available.
    final token = await messaging.getToken();
    if (token != null) await _register(token);

    _refreshSub?.cancel();
    _refreshSub = messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    _lastToken = token;
    final platform =
        kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
    try {
      await _ref
          .read(notificationsRepositoryProvider)
          .registerDevice(token: token, platform: platform);
      debugPrint('[FCM] Registered token (${platform}, len=${token.length})');
    } catch (e) {
      debugPrint('[FCM] register failed: $e');
    }
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _refreshSub = null;
    _foregroundSub = null;
    _openedSub = null;
    _registeredForUserId = null;
  }

  /// Called by `auth.signOut` so we drop the token server-side and stop
  /// fanning out pushes to the previous user's device.
  Future<void> unregister() async {
    final token = _lastToken;
    if (token == null) return;
    try {
      await _ref
          .read(notificationsRepositoryProvider)
          .unregisterDevice(token);
    } catch (e) {
      debugPrint('[FCM] unregister failed: $e');
    } finally {
      _lastToken = null;
      await dispose();
    }
  }

  void _onForegroundMessage(RemoteMessage msg) {
    // For MVP we surface foreground messages via debug log only.
    // A follow-up can wire flutter_local_notifications for an in-app
    // heads-up banner.
    debugPrint(
      '[FCM] foreground: ${msg.notification?.title ?? ''} - ${msg.notification?.body ?? ''}',
    );
  }

  void _onMessageTap(RemoteMessage msg) {
    final route = msg.data['route'];
    debugPrint('[FCM] tap, data=${msg.data}, route=$route');
    // Deep-link routing wiring lives outside the MVP - log so the dev
    // team can see what payload landed.
  }
}

final pushNotificationsServiceProvider = Provider<PushNotificationsService>(
  (ref) {
    final svc = PushNotificationsService(ref);
    ref.onDispose(svc.dispose);
    return svc;
  },
);
