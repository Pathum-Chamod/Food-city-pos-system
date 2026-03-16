import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showCheckoutPaymentDialog(
  BuildContext context, {
  required double totalAmount,
}) async {
  final amountController = TextEditingController(
    text: totalAmount.toStringAsFixed(2),
  );

  String selectedMethod = 'cash';
  double amountTendered = totalAmount;
  double changeAmount = 0.0;

  void recalculate() {
    if (selectedMethod == 'cash') {
      amountTendered = double.tryParse(amountController.text.trim()) ?? 0.0;
      changeAmount = math.max(0, amountTendered - totalAmount);
    } else {
      amountTendered = totalAmount;
      changeAmount = 0.0;
    }
  }

  recalculate();

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          recalculate();

          final canConfirm = selectedMethod == 'card'
              ? true
              : amountTendered >= totalAmount;

          return AlertDialog(
            title: const Text('Checkout Payment'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total: Rs. ${totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Payment Method',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Cash'),
                        selected: selectedMethod == 'cash',
                        onSelected: (_) {
                          setState(() {
                            selectedMethod = 'cash';
                            amountController.text =
                                totalAmount.toStringAsFixed(2);
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Card'),
                        selected: selectedMethod == 'card',
                        onSelected: (_) {
                          setState(() {
                            selectedMethod = 'card';
                            amountController.text =
                                totalAmount.toStringAsFixed(2);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (selectedMethod == 'cash') ...[
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount Tendered',
                        prefixText: 'Rs. ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      amountTendered < totalAmount
                          ? 'Remaining: Rs. ${(totalAmount - amountTendered).toStringAsFixed(2)}'
                          : 'Change: Rs. ${changeAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: amountTendered < totalAmount
                            ? Colors.red
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Card charge amount: Rs. ${totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.blue[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm
                    ? () {
                        Navigator.pop(context, {
                          'payment_method': selectedMethod,
                          'amount_tendered': selectedMethod == 'cash'
                              ? amountTendered
                              : totalAmount,
                          'change_amount': selectedMethod == 'cash'
                              ? changeAmount
                              : 0.0,
                        });
                      }
                    : null,
                child: const Text('Confirm Payment'),
              ),
            ],
          );
        },
      );
    },
  );

  amountController.dispose();
  return result;
}