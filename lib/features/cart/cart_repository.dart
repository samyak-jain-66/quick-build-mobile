import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/cart_models.dart';

class CartRepository {
  CartRepository(this._dio);
  final Dio _dio;

  Future<CartSummary> summary() async {
    final res = await _dio.get<Map<String, dynamic>>('/cart');
    return CartSummary.fromJson(res.data!);
  }

  Future<void> addItem({
    required String productId,
    required int quantity,
    String deliveryMode = 'standard',
  }) async {
    await _dio.post<void>('/cart/items', data: {
      'product_id': productId,
      'quantity': quantity,
      'delivery_mode': deliveryMode,
    });
  }

  Future<void> updateItem(String itemId, int quantity, {String? deliveryMode}) async {
    await _dio.patch<void>('/cart/items/$itemId', data: {
      'quantity': quantity,
      if (deliveryMode != null) 'delivery_mode': deliveryMode,
    });
  }

  Future<void> removeItem(String itemId) async {
    await _dio.delete<void>('/cart/items/$itemId');
  }

  Future<void> clear() async {
    await _dio.delete<void>('/cart');
  }

  Future<void> updateMeta({String? couponCode, bool? useWallet, String? notes}) async {
    await _dio.patch<void>('/cart/meta', data: {
      if (couponCode != null) 'coupon_code': couponCode,
      if (useWallet != null) 'use_wallet': useWallet,
      if (notes != null) 'notes': notes,
    });
  }

  /// Explicit set-or-clear variant that always sends `coupon_code` even when
  /// the caller passes `null`, so Supabase NULLs the column on clear. The
  /// generic `updateMeta` strips nulls because they're typically "unset" in
  /// that flow.
  Future<void> setCouponCode(String? code) async {
    await _dio.patch<void>('/cart/meta', data: {'coupon_code': code});
  }
}

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepository(ref.watch(apiClientProvider)),
);

class CartController extends StateNotifier<AsyncValue<CartSummary?>> {
  CartController(this._ref) : super(const AsyncValue.data(null)) {
    refresh();
  }

  final Ref _ref;
  CartRepository get _repo => _ref.read(cartRepositoryProvider);

  /// Generation counter used by `_silentRefresh`. Each optimistic mutation
  /// bumps the version so late-arriving refreshes from earlier taps are
  /// dropped in favour of the latest user action.
  int _reconcileVersion = 0;

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repo.summary());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Re-fetches the cart in the background without toggling the loading
  /// state. Used after optimistic updates so the UI can reconcile server-
  /// computed fields (tax, shipping, grand_total) without flashing a
  /// spinner. Stale responses from earlier calls are discarded.
  Future<void> _silentRefresh() async {
    final version = ++_reconcileVersion;
    try {
      final next = await _repo.summary();
      if (version == _reconcileVersion) {
        state = AsyncValue.data(next);
      }
    } catch (_) {
      // Swallow transient errors; the optimistic state stays on screen.
    }
  }

  Future<void> add({
    required String productId,
    required int quantity,
    String deliveryMode = 'standard',
  }) async {
    await _repo.addItem(
      productId: productId,
      quantity: quantity,
      deliveryMode: deliveryMode,
    );
    await refresh();
  }

  Future<void> update(String itemId, int quantity, {String? deliveryMode}) async {
    final snapshot = state.valueOrNull;
    if (snapshot != null) {
      state = AsyncValue.data(_withLocalQty(snapshot, itemId, quantity));
    }
    try {
      await _repo.updateItem(itemId, quantity, deliveryMode: deliveryMode);
      await _silentRefresh();
    } catch (e) {
      if (snapshot != null) state = AsyncValue.data(snapshot);
      rethrow;
    }
  }

  Future<void> remove(String itemId) async {
    final snapshot = state.valueOrNull;
    if (snapshot != null) {
      state = AsyncValue.data(_withLocalRemove(snapshot, itemId));
    }
    try {
      await _repo.removeItem(itemId);
      await _silentRefresh();
    } catch (e) {
      if (snapshot != null) state = AsyncValue.data(snapshot);
      rethrow;
    }
  }

  Future<void> clear() async {
    await _repo.clear();
    await refresh();
  }

  /// Applies or clears a coupon on the server cart and silently reconciles
  /// the summary (so totals, discount, and grand-total update without
  /// flashing a full-page loader).
  Future<void> setCoupon(String? code) async {
    await _repo.setCouponCode(code);
    await _silentRefresh();
  }
}

/// Returns a new [CartSummary] with the given item's quantity set to
/// [newQty]. Recomputes the affected line total, group subtotal, and
/// overall subtotal locally. Tax and shipping are left untouched here;
/// the silent refresh immediately after the PATCH brings them back in
/// sync with the server.
CartSummary _withLocalQty(CartSummary s, String itemId, int newQty) {
  double subtotal = 0;
  final groups = <CartGroup>[];
  for (final g in s.groups) {
    double gSub = 0;
    final items = <CartItem>[];
    for (final i in g.items) {
      if (i.id == itemId) {
        final lineTotal = i.unitPrice * newQty;
        items.add(CartItem(
          id: i.id,
          productId: i.productId,
          name: i.name,
          image: i.image,
          vendorId: i.vendorId,
          quantity: newQty,
          unitPrice: i.unitPrice,
          lineTotal: lineTotal,
          deliveryMode: i.deliveryMode,
          moq: i.moq,
        ));
        gSub += lineTotal;
      } else {
        items.add(i);
        gSub += i.lineTotal;
      }
    }
    groups.add(CartGroup(
      vendorId: g.vendorId,
      vendorName: g.vendorName,
      deliveryMode: g.deliveryMode,
      etaMinMinutes: g.etaMinMinutes,
      etaMaxMinutes: g.etaMaxMinutes,
      items: items,
      subtotal: gSub,
    ));
    subtotal += gSub;
  }
  return CartSummary(
    cartId: s.cartId,
    couponCode: s.couponCode,
    useWallet: s.useWallet,
    notes: s.notes,
    groups: groups,
    subtotal: subtotal,
    discountTotal: s.discountTotal,
    taxTotal: s.taxTotal,
    shippingTotal: s.shippingTotal,
    grandTotal: subtotal + s.taxTotal + s.shippingTotal - s.discountTotal,
  );
}

/// Returns a new [CartSummary] without the given item. Empty vendor
/// groups are dropped as well so the UI doesn't render empty cards.
CartSummary _withLocalRemove(CartSummary s, String itemId) {
  double subtotal = 0;
  final groups = <CartGroup>[];
  for (final g in s.groups) {
    final items = g.items.where((i) => i.id != itemId).toList(growable: false);
    if (items.isEmpty) continue;
    final gSub = items.fold<double>(0, (acc, i) => acc + i.lineTotal);
    groups.add(CartGroup(
      vendorId: g.vendorId,
      vendorName: g.vendorName,
      deliveryMode: g.deliveryMode,
      etaMinMinutes: g.etaMinMinutes,
      etaMaxMinutes: g.etaMaxMinutes,
      items: items,
      subtotal: gSub,
    ));
    subtotal += gSub;
  }
  return CartSummary(
    cartId: s.cartId,
    couponCode: s.couponCode,
    useWallet: s.useWallet,
    notes: s.notes,
    groups: groups,
    subtotal: subtotal,
    discountTotal: s.discountTotal,
    taxTotal: s.taxTotal,
    shippingTotal: s.shippingTotal,
    grandTotal: subtotal + s.taxTotal + s.shippingTotal - s.discountTotal,
  );
}

final cartControllerProvider =
    StateNotifierProvider<CartController, AsyncValue<CartSummary?>>(
  (ref) => CartController(ref),
);
