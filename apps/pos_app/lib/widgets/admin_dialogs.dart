import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class AdminDialogs {
  // Hardcoded for MVP. Later, we can store this in flutter_secure_storage
  static const String _adminPin = "1234"; 

  static Future<void> showPinDialog(BuildContext context, VoidCallback onSuccess) async {
    final TextEditingController pinController = TextEditingController();
    bool isError = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Admin Override Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter Manager PIN to modify inventory:'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'PIN',
                      errorText: isError ? 'Incorrect PIN' : null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (pinController.text == _adminPin) {
                      Navigator.pop(context); // Close PIN dialog
                      onSuccess(); // Trigger the next action
                    } else {
                      setState(() => isError = true);
                    }
                  },
                  child: const Text('Verify'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  static Future<void> showEditPriceDialog(BuildContext context, String barcode, String currentName, double currentPrice, VoidCallback onComplete) async {
    final TextEditingController priceController = TextEditingController(text: currentPrice.toString());

    await showDialog(
      context: context,
      builder: (context) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: Text('Edit Price: $currentName'),
          content: TextField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'New Price (Rs.)',
              prefixText: 'Rs. ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final newPrice = double.tryParse(priceController.text);
                if (newPrice != null && newPrice > 0) {
                  // Update DB locally and queue for cloud
                  await DatabaseHelper.instance.updateProductPriceLocal(barcode, newPrice);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  onComplete(); // Refresh the UI
                  
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Price updated locally and queued for sync!'), backgroundColor: Colors.green),
                  );
                }
              },
              child: const Text('Save Price', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
