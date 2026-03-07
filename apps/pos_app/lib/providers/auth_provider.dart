import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import '../services/database_helper.dart';

class AuthProvider with ChangeNotifier {
  User? _currentUser;
  
  User? get currentUser => _currentUser;

  // Checks the PIN against the database
  Future<bool> login(String pin) async {
    final userData = await DatabaseHelper.instance.authenticateUser(pin);
    if (userData != null) {
      _currentUser = User.fromMap(userData);
      notifyListeners();
      return true;
    }
    return false;
  }

  // Clears the session
  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
