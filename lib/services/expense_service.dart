import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ExpenseService {
  static const String _baseUrl = 'https://salestracker.kureone.com';
  static const Duration _timeout = Duration(seconds: 30);

  /// GET list of expenses for a user
  /// POST GetExpensesApi.htm?system_user_id=...
  Future<Map<String, dynamic>> getExpenses(int systemUserId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetExpensesApi.htm?system_user_id=$systemUserId',
      );

      final response = await http
          .post(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List) {
          return {'success': true, 'expenses': data['data'] as List};
        }
        return {'success': true, 'expenses': []};
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

  /// Fetch expense type master list
  /// POST GetExpenseTypesApi.htm?system_user_id=...
  Future<Map<String, dynamic>> getExpenseTypes(int systemUserId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetExpenseTypesApi.htm?system_user_id=$systemUserId',
      );

      final response = await http
          .post(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List) {
          return {'success': true, 'types': data['data'] as List};
        }
        return {'success': true, 'types': []};
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

  /// Add a new expense
  /// POST AddExpenseApi?system_user_id=...&date=dd/MM/yyyy&expense_type_id=...&amount=...
  /// photo as multipart file (optional)
  Future<Map<String, dynamic>> addExpense({
    required int systemUserId,
    required String date, // dd/MM/yyyy
    required int expenseTypeId,
    required double amount,
    String? photoPath,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/AddExpenseApi?'
        'system_user_id=$systemUserId&'
        'date=${Uri.encodeComponent(date)}&'
        'expense_type_id=$expenseTypeId&'
        'amount=$amount',
      );

      final request = http.MultipartRequest('POST', url);
      if (photoPath != null && photoPath.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath('photo', photoPath));
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
          if (data is Map<String, dynamic> && data['data'] is List) {
            final list = data['data'] as List;
            if (list.isNotEmpty && list[0] is Map) {
              final first = list[0] as Map<String, dynamic>;
              final msg = (first['message'] ?? '').toString();
              final expenseId = first['expense_id'];
              return {
                'success': true,
                'message': msg.isNotEmpty ? msg : 'Expense added successfully.',
                'expense_id': expenseId,
              };
            }
          }
        } catch (_) {}
        return {'success': true, 'message': 'Expense added successfully.'};
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
