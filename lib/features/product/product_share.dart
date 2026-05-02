import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hosts deep-link builders and native "share" helpers for products.
///
/// The app registers itself as a handler for links of the form:
///   * https://quick-build.app/p/<slug>     (web/universal link)
///   * quickbuild://product/<slug>           (custom scheme fallback)
///
/// When a user taps the link inside WhatsApp / SMS / email, Android will wake
/// the app up and [DeepLinkHandler] (see core/deeplink) routes them to the
/// matching product page.
class ProductShare {
  ProductShare._();

  static const String _webHost = 'https://quick-build.app';
  static const String _scheme = 'quickbuild';

  /// Public-facing HTTP URL (clickable in WhatsApp chats).
  static String webLink(String slug) => '$_webHost/p/$slug';

  /// Custom-scheme URL (opens the app directly on Android).
  static String appLink(String slug) => '$_scheme://product/$slug';

  /// Build the WhatsApp message body shared for a given product.
  static String buildMessage({
    required String name,
    required String slug,
    required double price,
    String? brand,
  }) {
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '\u20B9',
      decimalDigits: 0,
    );
    final brandLine = (brand != null && brand.trim().isNotEmpty)
        ? '\n$brand'
        : '';
    return 'Check out this on Quick-Build:$brandLine\n$name — ${fmt.format(price)}'
        '\n\nOrder in 10 minutes:\n${webLink(slug)}';
  }

  /// Opens WhatsApp with a pre-filled message so the user just picks a
  /// contact. Falls back to the native share sheet (and finally to copying
  /// the link to the clipboard) when WhatsApp isn't installed.
  ///
  /// Returns the [ShareOutcome] describing what actually happened so callers
  /// can show an appropriate snackbar.
  static Future<ShareOutcome> shareToWhatsApp({
    required String name,
    required String slug,
    required double price,
    String? brand,
  }) async {
    final message = buildMessage(
      name: name,
      slug: slug,
      price: price,
      brand: brand,
    );
    final encoded = Uri.encodeComponent(message);

    // Prefer wa.me because it's guaranteed to open WhatsApp's contact
    // picker (or prompt to install WhatsApp).
    final waMe = Uri.parse('https://wa.me/?text=$encoded');
    if (await canLaunchUrl(waMe)) {
      final ok = await launchUrl(
        waMe,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return ShareOutcome.whatsapp;
    }

    // Some devices only have the custom scheme registered.
    final scheme = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(scheme)) {
      final ok = await launchUrl(
        scheme,
        mode: LaunchMode.externalApplication,
      );
      if (ok) return ShareOutcome.whatsapp;
    }

    // Final fallback: copy the link so the user can paste it wherever.
    await Clipboard.setData(ClipboardData(text: webLink(slug)));
    return ShareOutcome.copiedToClipboard;
  }
}

enum ShareOutcome { whatsapp, copiedToClipboard }
