import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/catalog_models.dart';

class CategoriesRepository {
  CategoriesRepository(this._dio);
  final Dio _dio;

  Future<List<CategoryNode>> fetchTree() async {
    final res = await _dio.get<List<dynamic>>('/categories/tree');
    return (res.data ?? const [])
        .map((e) => CategoryNode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => CategoriesRepository(ref.watch(apiClientProvider)),
);

final categoriesTreeProvider = FutureProvider<List<CategoryNode>>((ref) {
  return ref.watch(categoriesRepositoryProvider).fetchTree();
});
