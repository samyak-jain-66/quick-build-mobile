import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/env/app_env.dart';
import 'orders_repository.dart';

/// Outcome of a payment attempt.
enum OrderPaymentResult { success, failed, cancelled }

/// Translates the app's internal payment-method code into a Razorpay
/// Checkout `method` restriction. Returns `null` when the user picked
/// "all" (or any value Razorpay does not gate) so the checkout shows
/// every instrument enabled on the merchant account.
///
/// Accepts: `upi`, `card`, `netbanking`, `wallet`. Anything else
/// (`all`, `cod`, unknown) falls through to `null`.
///
/// IMPORTANT: Razorpay's `method` map only gates an instrument when it
/// is explicitly set to `false`. Passing `{'upi': true}` alone still
/// shows Card / Net banking / Wallets / EMI / Pay Later because those
/// are enabled on the merchant account by default. So to truly limit
/// the checkout to a single method we set every other supported method
/// to `false`.
///
/// NOTE: We intentionally use the top-level `method` map instead of
/// `config.display.blocks`. The Razorpay Android SDK surfaced via
/// `razorpay_flutter` (1.3.7) silently fails to launch the checkout
/// when `display.blocks` is supplied, which was the root cause of UPI
/// not opening from this app.
Map<String, dynamic>? razorpayMethodRestriction(String method) {
  const methods = ['upi', 'card', 'netbanking', 'wallet', 'emi', 'paylater'];
  if (!methods.contains(method)) return null;
  return {
    'method': {
      for (final m in methods) m: m == method,
    },
  };
}

/// Encapsulates the Razorpay checkout + server-side verify dance for an
/// existing order. Reused by the orders list ("Pay now" button) and the
/// track-order screen so the flow stays consistent.
class OrderPaymentService {
  OrderPaymentService(this._ref);

  final Ref _ref;
  Razorpay? _razorpay;
  Completer<OrderPaymentResult>? _completer;
  String? _currentOrderId;

  OrdersRepository get _repo => _ref.read(ordersRepositoryProvider);

  Razorpay _ensureRazorpay() {
    return _razorpay ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onWallet);
  }

  Future<OrderPaymentResult> payForOrder({
    required String orderId,
    required String orderNumber,
    required double amount,
    String? method,
  }) async {
    if (_completer != null && !_completer!.isCompleted) {
      return OrderPaymentResult.cancelled;
    }
    _currentOrderId = orderId;
    _completer = Completer<OrderPaymentResult>();

    try {
      final payment = await _repo.createPayment(orderId);
      final razorpay = _ensureRazorpay();
      final options = <String, dynamic>{
        'key': payment['razorpay_key_id'] ?? AppEnv.razorpayKeyId,
        'order_id': payment['razorpay_order_id'],
        'amount': (amount * 100).round(),
        'currency': 'INR',
        'name': 'Quick-Build',
        'description': 'Order $orderNumber',
        'prefill': const <String, dynamic>{},
        'theme': const {'color': '#FFD600'},
      };
      final restriction =
          method == null ? null : razorpayMethodRestriction(method);
      if (restriction != null) options.addAll(restriction);
      razorpay.open(options);
    } catch (_) {
      _completer?.complete(OrderPaymentResult.failed);
    }

    return _completer!.future;
  }

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    final orderId = _currentOrderId;
    if (orderId == null) {
      _completer?.complete(OrderPaymentResult.failed);
      return;
    }
    try {
      await _repo.verifyPayment(
        orderId: orderId,
        razorpayOrderId: response.orderId ?? '',
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
      );
      _completer?.complete(OrderPaymentResult.success);
    } catch (_) {
      _completer?.complete(OrderPaymentResult.failed);
    }
  }

  void _onError(PaymentFailureResponse response) {
    // Razorpay uses code 2 for user-cancelled in addition to Code.NETWORK_ERROR
    // etc. We treat all non-success events as a cancellation so the UI can
    // silently return the user back to the screen with no scary error.
    _completer?.complete(OrderPaymentResult.cancelled);
  }

  void _onWallet(ExternalWalletResponse response) {
    // No-op: Razorpay surfaces success/error separately for wallets.
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}

final orderPaymentServiceProvider = Provider<OrderPaymentService>((ref) {
  final service = OrderPaymentService(ref);
  ref.onDispose(service.dispose);
  return service;
});
