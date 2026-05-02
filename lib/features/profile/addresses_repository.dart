import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class AddressModel {
  AddressModel({
    required this.id,
    required this.label,
    required this.line1,
    required this.city,
    required this.state,
    required this.pincode,
    required this.isDefault,
    required this.recipientName,
    required this.recipientPhone,
  });

  final String id;
  final String? label;
  final String line1;
  final String city;
  final String state;
  final String pincode;
  final bool isDefault;
  final String? recipientName;
  final String? recipientPhone;

  factory AddressModel.fromJson(Map<String, dynamic> j) => AddressModel(
        id: j['id'] as String,
        label: j['label'] as String?,
        line1: j['line1'] as String,
        city: j['city'] as String,
        state: j['state'] as String,
        pincode: j['pincode'] as String,
        isDefault: (j['is_default'] as bool?) ?? false,
        recipientName: j['recipient_name'] as String?,
        recipientPhone: j['recipient_phone'] as String?,
      );
}

class AddressesRepository {
  AddressesRepository(this._dio);
  final Dio _dio;

  Future<List<AddressModel>> list() async {
    final res = await _dio.get<List<dynamic>>('/addresses');
    return (res.data ?? const [])
        .map((e) => AddressModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AddressModel> create(Map<String, dynamic> payload) async {
    final res = await _dio.post<Map<String, dynamic>>('/addresses', data: payload);
    return AddressModel.fromJson(res.data!);
  }

  Future<void> delete(String id) => _dio.delete<void>('/addresses/$id');
}

final addressesRepositoryProvider = Provider<AddressesRepository>(
  (ref) => AddressesRepository(ref.watch(apiClientProvider)),
);

final addressesProvider = FutureProvider<List<AddressModel>>(
  (ref) => ref.watch(addressesRepositoryProvider).list(),
);
