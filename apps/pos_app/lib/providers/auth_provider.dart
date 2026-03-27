import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../services/database_helper.dart';

class AuthProvider with ChangeNotifier {
  User? _currentUser;
  String? _loginError;
  bool _inactiveLoginAttempt = false;

  User? get currentUser => _currentUser;
  String? get loginError => _loginError;
  bool get inactiveLoginAttempt => _inactiveLoginAttempt;

  bool get isLoggedIn => _currentUser != null;
  bool get isManager => _currentUser?.isManager ?? false;

  void clearLoginState() {
    _loginError = null;
    _inactiveLoginAttempt = false;
    notifyListeners();
  }

  Future<bool> login(String pin) async {
    final trimmedPin = pin.trim();

    _loginError = null;
    _inactiveLoginAttempt = false;

    if (!RegExp(r'^\d{4}$').hasMatch(trimmedPin)) {
      _currentUser = null;
      _loginError = 'Enter a valid 4-digit PIN.';
      notifyListeners();
      return false;
    }

    try {
      final existingUser = await DatabaseHelper.instance.findUserByPin(trimmedPin);

      if (existingUser == null) {
        await DatabaseHelper.instance.logLoginFailed(
          attemptedPin: trimmedPin,
          description: 'Failed login attempt for unknown PIN $trimmedPin',
        );

        _currentUser = null;
        _loginError = 'Invalid PIN.';
        notifyListeners();
        return false;
      }

      final isActive = ((existingUser['is_active'] as num?) ?? 1).toInt() == 1;
      final userName = (existingUser['name'] ?? 'User').toString();
      final userId = ((existingUser['id'] as num?) ?? 0).toInt();

      if (!isActive) {
        await DatabaseHelper.instance.logLoginFailed(
          attemptedPin: trimmedPin,
          description: 'Blocked login attempt for inactive user $userName',
        );

        _currentUser = null;
        _inactiveLoginAttempt = true;
        _loginError = 'This user is inactive. Please contact a manager.';
        notifyListeners();
        return false;
      }

      _currentUser = User.fromMap(existingUser);
      await DatabaseHelper.instance.logLoginSuccess(
        userId: userId,
        userName: userName,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Login error: $e');
      _currentUser = null;
      _loginError = 'Login failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final user = _currentUser;

    if (user != null && user.id != null) {
      try {
        await DatabaseHelper.instance.logLogout(
          userId: user.id!,
          userName: user.name,
        );
      } catch (e) {
        debugPrint('Logout log error: $e');
      }
    }

    _currentUser = null;
    _loginError = null;
    _inactiveLoginAttempt = false;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    final user = _currentUser;
    if (user?.id == null) return;

    try {
      final updated = await DatabaseHelper.instance.getUserById(user!.id!);

      if (updated == null) {
        _currentUser = null;
      } else {
        final isActive = ((updated['is_active'] as num?) ?? 1).toInt() == 1;
        _currentUser = isActive ? User.fromMap(updated) : null;
      }
    } catch (e) {
      debugPrint('Refresh current user error: $e');
    }

    notifyListeners();
  }
}
