import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/catalog_models.dart';

/// Repository for `/wishlist` endpoints.
class WishlistRepository {
  WishlistRepository(this._dio);
  final Dio _dio;

  /// Fetch the authenticated user's wishlisted products as [ProductSummary]s.
  Future<List<ProductSummary>> list() async {
    final res = await _dio.get<List<dynamic>>('/wishlist');
    return (res.data ?? const [])
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Cheap bulk check -> which product-ids are in the user's wishlist.
  Future<Set<String>> ids() async {
    final res = await _dio.get<List<dynamic>>('/wishlist/ids');
    return (res.data ?? const []).map((e) => e.toString()).toSet();
  }

  Future<void> add(String productId) async {
    await _dio.post<dynamic>(
      '/wishlist',
      data: {'product_id': productId},
    );
  }

  Future<void> remove(String productId) async {
    await _dio.delete<dynamic>('/wishlist/$productId');
  }
}

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => WishlistRepository(ref.watch(apiClientProvider)),
);

/// The set of product-ids the current user has wishlisted. Kept small/cheap
/// so individual product cards / detail screens can subscribe and render the
/// heart in the correct filled/outlined state.
class WishlistIdsController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    try {
      return await ref.read(wishlistRepositoryProvider).ids();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return <String>{};
      }
      rethrow;
    }
  }

  bool contains(String productId) {
    return state.maybeWhen(
      data: (ids) => ids.contains(productId),
      orElse: () => false,
    );
  }

  /// Optimistically toggle the wishlist entry; on failure, rolls back and
  /// rethrows so the UI can surface a snackbar.
  Future<bool> toggle(String productId) async {
    final repo = ref.read(wishlistRepositoryProvider);
    final current = state.valueOrNull ?? <String>{};
    final isAdding = !current.contains(productId);

    final next = {...current};
    if (isAdding) {
      next.add(productId);
    } else {
      next.remove(productId);
    }
    state = AsyncData(next);

    try {
      if (isAdding) {
        await repo.add(productId);
      } else {
        await repo.remove(productId);
      }
      // Refresh the detailed list so the WishlistScreen stays in sync.
      ref.invalidate(wishlistListProvider);
      return isAdding;
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(wishlistRepositoryProvider).ids(),
    );
  }
}

final wishlistIdsProvider =
    AsyncNotifierProvider<WishlistIdsController, Set<String>>(
  WishlistIdsController.new,
);

/// Full product details for each wishlisted item. Used by `WishlistScreen`.
final wishlistListProvider =
    FutureProvider.autoDispose<List<ProductSummary>>((ref) {
  return ref.watch(wishlistRepositoryProvider).list();
});
