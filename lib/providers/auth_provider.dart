import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'trip_provider.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _user;
  bool _isLoading = false;
  bool _isInitializing = true;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _loadUser();
  }

  Future<void> _loadUser() async {
    _isInitializing = true;
    notifyListeners();
    _user = await _authService.getUser();
    _isInitializing = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.login(username, password);

    if (result['success']) {
      _user = result['user'];
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_user == null) {
      return {'success': false, 'message': 'User not logged in'};
    }

    _isLoading = true;
    notifyListeners();

    final result = await _authService.changePassword(
      systemUserId: _user!.systemUserId,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> forgotPassword(String username) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.forgotPassword(username);

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> resetPassword({
    required int systemUserId,
    required String otp,
    required String newPassword,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _authService.resetPassword(
      systemUserId: systemUserId,
      otp: otp,
      newPassword: newPassword,
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<void> logout({TripProvider? tripProvider}) async {
    // Stop background trip tracking before clearing the user session
    await tripProvider?.cleanupOnLogout();
    await _authService.logout();
    _user = null;
    notifyListeners();
  }
}
