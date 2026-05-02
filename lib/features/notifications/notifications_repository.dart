import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class NotificationsRepository {
  NotificationsRepository(this._dio);
  final Dio _dio;

  Future<void> registerDevice({
    required String token,
    required String platform,
  }) async {
    await _dio.post<void>(
      '/notifications/devices',
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> unregisterDevice(String token) async {
    await _dio.delete<void>('/notifications/devices/$token');
  }

  Future<void> sendTest({String? title, String? body}) async {
    await _dio.post<void>(
      '/notifications/test',
      data: {
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      },
    );
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);
