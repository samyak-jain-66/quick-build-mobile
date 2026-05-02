import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> placeOrder({
    required String addressId,
    required String paymentMethod,
    bool gstInvoice = false,
    String? gstin,
    String? businessName,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/orders',
      data: {
        'address_id': addressId,
        'payment_method': paymentMethod,
        if (gstInvoice) 'gst_invoice_requested': true,
        if (gstin != null) 'gstin': gstin,
        if (businessName != null) 'business_name': businessName,
        if (notes != null) 'notes': notes,
      },
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> buyNow({
    required String productId,
    required int quantity,
    required String addressId,
    required String paymentMethod,
    String deliveryMode = 'standard',
    bool gstInvoice = false,
    String? gstin,
    String? businessName,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/orders/buy-now',
      data: {
        'product_id': productId,
        'quantity': quantity,
        'address_id': addressId,
        'payment_method': paymentMethod,
        'delivery_mode': deliveryMode,
        if (gstInvoice) 'gst_invoice_requested': true,
        if (gstin != null) 'gstin': gstin,
        if (businessName != null) 'business_name': businessName,
        if (notes != null) 'notes': notes,
      },
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> createPayment(String orderId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/payments/create',
      data: {'order_id': orderId},
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/payments/verify',
      data: {
        'order_id': orderId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
    );
    return res.data!;
  }

  Future<List<Map<String, dynamic>>> list() async {
    final res = await _dio.get<List<dynamic>>('/orders');
    return (res.data ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> detail(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/orders/$id');
    return res.data!;
  }

  /// Lists the reviews the current user has already submitted for
  /// products in this order. Used by the rate-products bottom sheet to
  /// gray out rows that are already rated.
  Future<List<Map<String, dynamic>>> myReviewsForOrder(String orderId) async {
    final res = await _dio.get<List<dynamic>>('/reviews/orders/$orderId');
    return (res.data ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Submits a 1-5 star review for a single product against a delivered
  /// order. Trips the (user_id, product_id, order_id) unique constraint
  /// on duplicates - callers can swallow that 4xx as 'already rated'.
  Future<void> submitProductReview({
    required String productId,
    required String orderId,
    required int rating,
    String? body,
  }) async {
    await _dio.post<void>('/reviews', data: {
      'product_id': productId,
      'order_id': orderId,
      'rating': rating,
      if (body != null && body.isNotEmpty) 'body': body,
    });
  }

  /// Submits a 1-5 star rating + optional comment for the rider that
  /// delivered this order. Returns the rider's new rolling-average
  /// rating after the trigger updates it.
  Future<double> submitRiderFeedback(
    String orderId, {
    required int rating,
    String? comment,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/orders/$orderId/rider-feedback',
      data: {
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
    return ((res.data?['new_rating'] as num?) ?? 0).toDouble();
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);

final ordersListProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(ordersRepositoryProvider).list(),
);

final orderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).detail(id),
);

/// Reviews the current user has already submitted for products in this
/// order. Drives the "Rate the products" CTA's two states (button vs
/// muted "You rated this order").
final myOrderReviewsProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, orderId) async {
  return ref.watch(ordersRepositoryProvider).myReviewsForOrder(orderId);
});
