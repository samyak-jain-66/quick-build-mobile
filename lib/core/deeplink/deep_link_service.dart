import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';

/// Singleton that listens for incoming deep links (`quickbuild://product/...`
/// or `https://quick-build.app/p/...`) and pushes the matching route on the
/// GoRouter.
///
/// Works with both the initial-launch link (when the app is cold-started from
/// a tap) and subsequent taps while the app is already running.
class DeepLinkService {
  DeepLinkService(this._ref);

  final Ref _ref;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialHandled = false;

  Future<void> start() async {
    _sub ??= _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) =>
          debugPrint('[DeepLink] stream error: $e'),
    );

    if (!_initialHandled) {
      _initialHandled = true;
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) _handle(initial);
      } catch (e) {
        debugPrint('[DeepLink] initial error: $e');
      }
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    debugPrint('[DeepLink] handling: $uri');
    final route = _routeForUri(uri);
    if (route == null) return;
    final router = _ref.read(goRouterProvider);
    // Use push (not go) so the deep-linked page sits above the home tabs and
    // the user can easily back out of it.
    router.push(route);
  }

  /// Translate a deep-link URI into an in-app route. Returns null if the URI
  /// doesn't match any known pattern.
  static String? _routeForUri(Uri uri) {
    // quickbuild://product/<slug>
    if (uri.scheme == 'quickbuild' && uri.host == 'product') {
      final slug = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (slug != null && slug.isNotEmpty) return '/product/$slug';
    }
    // https://quick-build.app/p/<slug>
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'quick-build.app' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'p') {
      final slug = uri.pathSegments[1];
      if (slug.isNotEmpty) return '/product/$slug';
    }
    return null;
  }
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(ref);
  ref.onDispose(service.dispose);
  return service;
});
