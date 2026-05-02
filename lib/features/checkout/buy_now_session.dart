import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Snapshot of the product the user tapped "Buy Now" on. Kept in memory
/// so the existing [CheckoutScreen] can render a one-item preview and
/// compute totals without hitting the cart table on the server.
class BuyNowSession {
  const BuyNowSession({
    required this.productId,
    required this.productName,
    required this.image,
    required this.vendorId,
    required this.vendorName,
    required this.quantity,
    required this.unitPrice,
    required this.taxPct,
    required this.deliveryMode,
    required this.etaMinMinutes,
    required this.etaMaxMinutes,
  });

  final String productId;
  final String productName;
  final String? image;
  final String vendorId;
  final String vendorName;
  final int quantity;
  final double unitPrice;
  final double taxPct;
  final String deliveryMode;
  final int etaMinMinutes;
  final int etaMaxMinutes;

  double get subtotal => unitPrice * quantity;
  double get taxTotal => subtotal * taxPct / 100;
  double get shippingTotal {
    switch (deliveryMode) {
      case 'express':
        return 49;
      case 'same_day':
        return 29;
      default:
        return 0;
    }
  }

  double get grandTotal => subtotal + taxTotal + shippingTotal;
}

final buyNowSessionProvider = StateProvider<BuyNowSession?>((_) => null);
