import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _enteredPin = "";

  void _onKeyPress(String value) {
    setState(() {
      if (value == "CLEAR") {
        _enteredPin = "";
      } else if (value == "DEL") {
        if (_enteredPin.isNotEmpty) {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        }
      } else {
        if (_enteredPin.length < 4) {
          _enteredPin += value;
        }
      }
    });

    // Auto-submit when exactly 4 digits are entered
    if (_enteredPin.length == 4) {
      _attemptLogin();
    }
  }

  Future<void> _attemptLogin() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final success = await context.read<AuthProvider>().login(_enteredPin);
    
    if (success) {
      if (!context.mounted) return;
      // Navigate to the POS screen and remove the login screen from the back-stack
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const PosScreen()),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('❌ Invalid PIN. Please try again.'), 
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _enteredPin = ""; // Clear pin on failure so they can try again
      });
    }
  }

  Widget _buildKey(String value) {
    final isAction = value == 'CLEAR' || value == 'DEL';
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isAction ? Colors.grey[200] : Colors.white,
          foregroundColor: isAction ? Colors.red[700] : Colors.black,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        onPressed: () => _onKeyPress(value),
        child: value == 'CLEAR'
            ? const Icon(Icons.refresh, size: 26)
            : value == 'DEL'
                ? const Icon(Icons.backspace_outlined, size: 24)
                : Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person, size: 60, color: Colors.blueAccent),
                const SizedBox(height: 12),
                const Text('Employee Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Enter your 4-digit PIN to access register', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                
                // PIN Dot Indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _enteredPin.length ? Colors.blueAccent : Colors.grey[300],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                
                // Keypad Grid
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  childAspectRatio: 1.8,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildKey('1'), _buildKey('2'), _buildKey('3'),
                    _buildKey('4'), _buildKey('5'), _buildKey('6'),
                    _buildKey('7'), _buildKey('8'), _buildKey('9'),
                    _buildKey('CLEAR'), _buildKey('0'), _buildKey('DEL'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
