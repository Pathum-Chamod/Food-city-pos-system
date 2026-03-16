import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showCartDiscountDialog(
  BuildContext context, {
  required double subtotal,
  required String currentDiscountType,
  required double currentDiscountValue,
}) async {
  final valueController = TextEditingController(
    text: currentDiscountType == 'none'
        ? ''
        : currentDiscountValue.toStringAsFixed(
            currentDiscountValue % 1 == 0 ? 0 : 2,
          ),
  );

  String selectedType = currentDiscountType;

  double calculateDiscountAmount({
    required double subtotal,
    required String type,
    required double value,
  }) {
    if (subtotal <= 0) return 0.0;

    if (type == 'fixed') {
      final double safe = value < 0 ? 0.0 : value;
      return safe > subtotal ? subtotal : safe;
    }

    if (type == 'percent') {
      final double safe = value < 0 ? 0.0 : value;
      final double capped = safe > 100.0 ? 100.0 : safe;
      return subtotal * (capped / 100.0);
    }

    return 0.0;
  }

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final enteredValue =
              double.tryParse(valueController.text.trim()) ?? 0.0;
          final discountAmount = calculateDiscountAmount(
            subtotal: subtotal,
            type: selectedType,
            value: enteredValue,
          );
          final total = subtotal - discountAmount;

          return AlertDialog(
            title: const Text('Apply Discount'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subtotal: Rs. ${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('No Discount'),
                        selected: selectedType == 'none',
                        onSelected: (_) {
                          setState(() {
                            selectedType = 'none';
                            valueController.clear();
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Fixed Amount'),
                        selected: selectedType == 'fixed',
                        onSelected: (_) {
                          setState(() {
                            selectedType = 'fixed';
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Percentage'),
                        selected: selectedType == 'percent',
                        onSelected: (_) {
                          setState(() {
                            selectedType = 'percent';
                          });
                        },
                      ),
                    ],
                  ),
                  if (selectedType != 'none') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: valueController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: selectedType == 'fixed'
                            ? 'Discount Amount'
                            : 'Discount Percentage',
                        prefixText: selectedType == 'fixed' ? 'Rs. ' : null,
                        suffixText: selectedType == 'percent' ? '%' : null,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Discount: Rs. ${discountAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total After Discount: Rs. ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final cleanValue =
                      double.tryParse(valueController.text.trim()) ?? 0.0;

                  Navigator.pop(context, {
                    'discount_type': selectedType,
                    'discount_value': selectedType == 'none' ? 0.0 : cleanValue,
                  });
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );

  valueController.dispose();
  return result;
}
