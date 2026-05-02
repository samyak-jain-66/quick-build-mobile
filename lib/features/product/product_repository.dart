import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/catalog_models.dart';

class ProductRepository {
  ProductRepository(this._dio);
  final Dio _dio;

  Future<ProductDetail> fetch(String slug) async {
    final res = await _dio.get<Map<String, dynamic>>('/products/$slug');
    return ProductDetail.fromJson(res.data!);
  }

  Future<List<ProductSummary>> similar(String slug) async {
    final res = await _dio.get<List<dynamic>>('/products/$slug/similar');
    return (res.data ?? const [])
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ProductSummary>> fbt(String slug) async {
    final res = await _dio.get<List<dynamic>>(
      '/products/$slug/frequently-bought-together',
    );
    return (res.data ?? const [])
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ProductSummary>> listByCategory(String slug,
      {int limit = 24, int offset = 0}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/products',
      queryParameters: {
        'category': slug,
        'limit': limit,
        'offset': offset,
      },
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ProductSummary>> listFiltered(
    String slug, {
    required ProductListFilters filters,
    int limit = 24,
    int offset = 0,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/products',
      queryParameters: {
        'category': slug,
        'limit': limit,
        'offset': offset,
        ...filters.toQuery(),
      },
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ProductSummary>> featured() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/products',
      queryParameters: {'limit': 12, 'sort': 'newest'},
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> reviews(String productId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/reviews/products/$productId',
    );
    return res.data ?? const {};
  }
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(apiClientProvider)),
);

final productDetailProvider =
    FutureProvider.family<ProductDetail, String>((ref, slug) {
  return ref.watch(productRepositoryProvider).fetch(slug);
});

final similarProductsProvider =
    FutureProvider.family<List<ProductSummary>, String>((ref, slug) {
  return ref.watch(productRepositoryProvider).similar(slug);
});

final fbtProductsProvider =
    FutureProvider.family<List<ProductSummary>, String>((ref, slug) {
  return ref.watch(productRepositoryProvider).fbt(slug);
});

enum ProductSort { relevance, priceAsc, priceDesc, newest }

enum PriceBucket { any, under100, between100And500, between500And2k, above2k }

class ProductListFilters {
  const ProductListFilters({
    this.sort = ProductSort.relevance,
    this.priceBucket = PriceBucket.any,
    this.expressOnly = false,
    this.brandSlug,
  });

  final ProductSort sort;
  final PriceBucket priceBucket;
  final bool expressOnly;
  final String? brandSlug;

  ProductListFilters copyWith({
    ProductSort? sort,
    PriceBucket? priceBucket,
    bool? expressOnly,
    String? brandSlug,
    bool clearBrand = false,
  }) {
    return ProductListFilters(
      sort: sort ?? this.sort,
      priceBucket: priceBucket ?? this.priceBucket,
      expressOnly: expressOnly ?? this.expressOnly,
      brandSlug: clearBrand ? null : (brandSlug ?? this.brandSlug),
    );
  }

  bool get isActive =>
      sort != ProductSort.relevance ||
      priceBucket != PriceBucket.any ||
      expressOnly ||
      (brandSlug != null && brandSlug!.isNotEmpty);

  int get activeCount {
    var count = 0;
    if (sort != ProductSort.relevance) count++;
    if (priceBucket != PriceBucket.any) count++;
    if (expressOnly) count++;
    if (brandSlug != null && brandSlug!.isNotEmpty) count++;
    return count;
  }

  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{};
    switch (sort) {
      case ProductSort.priceAsc:
        q['sort'] = 'price_asc';
        break;
      case ProductSort.priceDesc:
        q['sort'] = 'price_desc';
        break;
      case ProductSort.newest:
        q['sort'] = 'newest';
        break;
      case ProductSort.relevance:
        break;
    }
    switch (priceBucket) {
      case PriceBucket.under100:
        q['price_max'] = 100;
        break;
      case PriceBucket.between100And500:
        q['price_min'] = 100;
        q['price_max'] = 500;
        break;
      case PriceBucket.between500And2k:
        q['price_min'] = 500;
        q['price_max'] = 2000;
        break;
      case PriceBucket.above2k:
        q['price_min'] = 2000;
        break;
      case PriceBucket.any:
        break;
    }
    if (expressOnly) q['express_only'] = true;
    if (brandSlug != null && brandSlug!.isNotEmpty) q['brand'] = brandSlug;
    return q;
  }

  @override
  bool operator ==(Object other) {
    return other is ProductListFilters &&
        other.sort == sort &&
        other.priceBucket == priceBucket &&
        other.expressOnly == expressOnly &&
        other.brandSlug == brandSlug;
  }

  @override
  int get hashCode => Object.hash(sort, priceBucket, expressOnly, brandSlug);
}

class FilteredProductsKey {
  const FilteredProductsKey(this.slug, this.filters);
  final String slug;
  final ProductListFilters filters;

  @override
  bool operator ==(Object other) =>
      other is FilteredProductsKey &&
      other.slug == slug &&
      other.filters == filters;

  @override
  int get hashCode => Object.hash(slug, filters);
}

final filteredCategoryProductsProvider = FutureProvider.autoDispose
    .family<List<ProductSummary>, FilteredProductsKey>((ref, key) {
  return ref
      .watch(productRepositoryProvider)
      .listFiltered(key.slug, filters: key.filters);
});

final featuredProductsProvider = FutureProvider<List<ProductSummary>>((ref) {
  return ref.watch(productRepositoryProvider).featured();
});

final productReviewsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, productId) {
  return ref.watch(productRepositoryProvider).reviews(productId);
});
