import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AttendanceService {
  static const String _baseUrl = 'https://salestracker.kureone.com';
  static const Duration _timeout = Duration(seconds: 30);

  /// Punch In API
  /// POST PunchInApi with query params and multipart form-data photo file
  Future<Map<String, dynamic>> punchIn({
    required int systemUserId,
    required double latitude,
    required double longitude,
    required String photoPath,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/PunchInApi?'
        'system_user_id=$systemUserId&'
        'latitude=$latitude&'
        'longitude=$longitude',
      );

      final request = http.MultipartRequest('POST', url);
      request.files.add(await http.MultipartFile.fromPath('photo', photoPath));

      final streamed = await request.send().timeout(
        _timeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection is slow. Please check your internet connection.',
          );
        },
      );

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic>) {
            final message = data['message']?.toString() ?? '';
            final dataList = data['data'];
            if (dataList is List && dataList.isNotEmpty) {
              final first = dataList[0];
              if (first is Map<String, dynamic>) {
                final msg = first['message']?.toString() ?? message;
                final success =
                    msg.toLowerCase().contains('success') ||
                    msg.toLowerCase().contains('punch') ||
                    msg.toLowerCase().contains('check');
                return {
                  'success': success,
                  'message': msg.isNotEmpty ? msg : 'Punch-in recorded.',
                };
              }
            }
            return {
              'success': true,
              'message': message.isNotEmpty ? message : 'Punch-in recorded.',
            };
          }
        } catch (_) {}
        return {'success': true, 'message': 'Punch-in recorded.'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Punch Out API
  /// POST PunchOutApi with query params and optional multipart form-data photo
  Future<Map<String, dynamic>> punchOut({
    required int systemUserId,
    required double latitude,
    required double longitude,
    String? photoPath,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/PunchOutApi?'
        'system_user_id=$systemUserId&'
        'latitude=$latitude&'
        'longitude=$longitude',
      );

      final request = http.MultipartRequest('POST', url);
      if (photoPath != null && photoPath.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', photoPath),
        );
      }

      final streamed = await request.send().timeout(
        _timeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection is slow. Please check your internet connection.',
          );
        },
      );

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          if (data is Map<String, dynamic>) {
            final message = data['message']?.toString() ?? '';
            final dataList = data['data'];
            if (dataList is List && dataList.isNotEmpty) {
              final first = dataList[0];
              if (first is Map<String, dynamic>) {
                final msg = first['message']?.toString() ?? message;
                final success =
                    msg.toLowerCase().contains('success') ||
                    msg.toLowerCase().contains('punch') ||
                    msg.toLowerCase().contains('check');
                return {
                  'success': success,
                  'message': msg.isNotEmpty ? msg : 'Punch-out recorded.',
                };
              }
            }
            return {
              'success': true,
              'message': message.isNotEmpty ? message : 'Punch-out recorded.',
            };
          }
        } catch (_) {}
        return {'success': true, 'message': 'Punch-out recorded.'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Get last punch-in status for a user
  /// GET GetLastPunchInStatusApi.htm?system_user_id=...
  /// Example response:
  /// {
  ///   "data": [ { "time": "12:52 PM", "punch_in_id": 12, "status": "PUNCH OUT", "date": "16/03/2026" } ]
  /// }
  Future<Map<String, dynamic>> getLastPunchStatus(int systemUserId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetLastPunchInStatusApi.htm?system_user_id=$systemUserId',
      );

      final response = await http
          .get(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List) {
          final list = data['data'] as List;
          if (list.isNotEmpty && list.first is Map<String, dynamic>) {
            final Map<String, dynamic> first = Map<String, dynamic>.from(
              list.first as Map,
            );
            final status = (first['status'] ?? '').toString().toUpperCase();
            final isClockedIn = status == 'PUNCH IN';
            return {'success': true, 'isClockedIn': isClockedIn, 'raw': first};
          }
        }
        // No data means no punches yet; treat as not clocked in.
        return {'success': true, 'isClockedIn': false, 'raw': null};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }
}
