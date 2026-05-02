import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/catalog_models.dart';

class SearchSuggestion {
  const SearchSuggestion({required this.name, required this.slug});
  final String name;
  final String slug;
}

class SearchRepository {
  SearchRepository(this._dio);
  final Dio _dio;

  Future<List<SearchSuggestion>> suggest(String q) async {
    if (q.trim().length < 2) return const [];
    final res = await _dio.get<List<dynamic>>(
      '/search/suggest',
      queryParameters: {'q': q},
    );
    final raw = res.data ?? const [];
    return raw.map<SearchSuggestion?>((e) {
      if (e is Map) {
        final name = e['name']?.toString();
        final slug = e['slug']?.toString();
        if (name == null || slug == null || slug.isEmpty) return null;
        return SearchSuggestion(name: name, slug: slug);
      }
      return null;
    }).whereType<SearchSuggestion>().toList();
  }

  Future<({List<ProductSummary> items, Map<String, dynamic> facets, int total})> run({
    String? q,
    String? brand,
    String? category,
    double? priceMin,
    double? priceMax,
    bool? expressOnly,
    int limit = 24,
    int offset = 0,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/search',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (brand != null) 'brand': brand,
        if (category != null) 'category': category,
        if (priceMin != null) 'price_min': priceMin,
        if (priceMax != null) 'price_max': priceMax,
        if (expressOnly == true) 'express_only': 'true',
        'limit': limit,
        'offset': offset,
      },
    );
    final items = ((res.data?['items'] as List?) ?? const [])
        .map((e) => ProductSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (
      items: items,
      facets: Map<String, dynamic>.from(res.data?['facets'] ?? {}),
      total: (res.data?['total'] as num?)?.toInt() ?? 0,
    );
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider)),
);
