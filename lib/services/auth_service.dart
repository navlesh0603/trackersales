import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _baseUrl = 'https://salestracker.kureone.com';
  static const String _userKey = 'user_data';
  static const String _passwordKey = 'user_password';
  static const Duration _timeout = Duration(seconds: 30);

  // Login API
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/LoginApi.htm?username=$username&password=$password',
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
        // Log the response for debugging (will show in terminal)
        print('Login API Response: ${response.body}');

        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final userData = (data['data'] as List)[0];

          if (userData is Map<String, dynamic>) {
            final message = userData['message']?.toString().trim() ?? '';

            // Flexibly check for success message
            if (message.toLowerCase().contains('login successful')) {
              final user = UserModel.fromJson(userData);
              await _saveUser(user);
              await _savePassword(password);
              return {'success': true, 'user': user, 'message': message};
            } else {
              // This handles the "Invalid Login Details." case
              return {
                'success': false,
                'message': message.isNotEmpty ? message : 'Login failed',
              };
            }
          }
        }

        return {
          'success': false,
          'message': 'Invalid credentials or account not found.',
        };
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

  // Change Password API
  Future<Map<String, dynamic>> changePassword({
    required int systemUserId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/ChangePasswordApi.htm?system_user_id=$systemUserId&old_password=$oldPassword&new_password=$newPassword',
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

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final result = (data['data'] as List)[0];

          if (result is Map<String, dynamic>) {
            final message = result['message']?.toString() ?? '';

            // Check for success messages
            if (message.toLowerCase().contains('success') ||
                message.toLowerCase().contains('changed')) {
              await _savePassword(newPassword); // Update saved password
              return {'success': true, 'message': message};
            } else {
              return {
                'success': false,
                'message': message.isNotEmpty
                    ? message
                    : 'Password change failed',
              };
            }
          }
        }

        return {'success': false, 'message': 'Invalid response from server'};
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

  // Forgot Password API (generates OTP)
  Future<Map<String, dynamic>> forgotPassword(String username) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/ForgotPasswordApi.htm?username=$username',
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

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final result = (data['data'] as List)[0];

          if (result is Map<String, dynamic>) {
            final message = result['message']?.toString() ?? '';
            final otp = result['otp']?.toString() ?? '';
            final systemUserId =
                (result['system_user_id'] as num?)?.toInt() ?? 0;

            if (message.toLowerCase().contains('otp') && otp.isNotEmpty) {
              return {
                'success': true,
                'message': message,
                'otp': otp,
                'system_user_id': systemUserId,
              };
            } else {
              return {
                'success': false,
                'message': message.isNotEmpty ? message : 'Failed to send OTP',
              };
            }
          }
        }

        return {'success': false, 'message': 'Invalid response from server'};
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

  // Reset Password API (with OTP)
  Future<Map<String, dynamic>> resetPassword({
    required int systemUserId,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/ResetPasswordApi.htm?system_user_id=$systemUserId&otp=$otp&new_password=$newPassword',
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

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final result = (data['data'] as List)[0];

          if (result is Map<String, dynamic>) {
            final message = result['message']?.toString() ?? '';

            // Check for success messages
            if (message.toLowerCase().contains('success') ||
                message.toLowerCase().contains('reset')) {
              return {'success': true, 'message': message};
            } else {
              return {
                'success': false,
                'message': message.isNotEmpty
                    ? message
                    : 'Password reset failed',
              };
            }
          }
        }

        return {'success': false, 'message': 'Invalid response from server'};
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

  // Save user data to SharedPreferences
  Future<void> _saveUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }

  // Save password to SharedPreferences (for session persistence)
  Future<void> _savePassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordKey, password);
  }

  // Get user data from SharedPreferences
  Future<UserModel?> getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(_userKey);
      if (userData != null) {
        final decoded = json.decode(userData);
        if (decoded is Map<String, dynamic>) {
          return UserModel.fromJson(decoded);
        }
      }
    } catch (e) {
      // Silently fail and return null if data is corrupted
    }
    return null;
  }

  // Get saved password
  Future<String?> getSavedPassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_passwordKey);
    } catch (e) {
      return null;
    }
  }

  // Logout - clear all saved data
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_passwordKey);
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_userKey);
  }
}
