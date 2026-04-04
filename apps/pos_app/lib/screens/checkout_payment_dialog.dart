import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/card_terminal_service.dart';

Future<Map<String, dynamic>?> showCheckoutPaymentDialog(
  BuildContext context, {
  required double totalAmount,
  Future<void> Function()? onOpenHardwareSetup,
}) async {
  final amountController = TextEditingController(
    text: totalAmount.toStringAsFixed(2),
  );

  String selectedMethod = 'cash';
  double amountTendered = totalAmount;
  double changeAmount = 0.0;
  bool isProcessingCard = false;
  String? cardStatusMessage;

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
          final terminal = CardTerminalService.instance;

          Future<void> processCardPayment() async {
            if (isProcessingCard) return;

            if (!terminal.isConnected) {
              setState(() {
                cardStatusMessage =
                    'Card terminal is not connected. Open hardware setup and connect the terminal first.';
              });
              return;
            }

            setState(() {
              isProcessingCard = true;
              cardStatusMessage = 'Waiting for terminal response...';
            });

            final response = await terminal.requestSale(totalAmount);

            if (!context.mounted) return;

            setState(() {
              isProcessingCard = false;
              cardStatusMessage = response.message;
            });

            switch (response.result) {
              case CardTransactionResult.approved:
                Navigator.pop(context, {
                  'payment_method': 'card',
                  'amount_tendered': totalAmount,
                  'change_amount': 0.0,
                  'approval_code': response.approvalCode,
                  'auth_code': response.authCode,
                  'card_last4': response.cardLast4,
                  'card_type': response.cardType,
                });
                return;
              case CardTransactionResult.declined:
              case CardTransactionResult.cancelled:
              case CardTransactionResult.timeout:
              case CardTransactionResult.error:
                return;
            }
          }

          final canConfirm = selectedMethod == 'card'
              ? !isProcessingCard
              : amountTendered >= totalAmount;

          return AlertDialog(
            title: const Text('Checkout Payment'),
            content: SizedBox(
              width: 440,
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
                        onSelected: isProcessingCard
                            ? null
                            : (_) {
                                setState(() {
                                  selectedMethod = 'cash';
                                  amountController.text =
                                      totalAmount.toStringAsFixed(2);
                                  cardStatusMessage = null;
                                });
                              },
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Card'),
                        selected: selectedMethod == 'card',
                        onSelected: isProcessingCard
                            ? null
                            : (_) {
                                setState(() {
                                  selectedMethod = 'card';
                                  amountController.text =
                                      totalAmount.toStringAsFixed(2);
                                  cardStatusMessage = null;
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
                        color: terminal.isConnected
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: terminal.isConnected
                              ? Colors.green.shade200
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Card charge amount: Rs. ${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.blue[800],
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            terminal.isConnected
                                ? 'Terminal connected on ${terminal.connectedPortName}'
                                : 'Card terminal is not connected.',
                            style: TextStyle(
                              color: terminal.isConnected
                                  ? Colors.green[800]
                                  : Colors.orange[900],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ElevatedButton.icon(
                                onPressed: isProcessingCard
                                    ? null
                                    : () => processCardPayment(),
                                icon: isProcessingCard
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.credit_card),
                                label: Text(
                                  isProcessingCard
                                      ? 'Processing...'
                                      : 'Charge Card',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: isProcessingCard || onOpenHardwareSetup == null
                                    ? null
                                    : () async {
                                        await onOpenHardwareSetup();
                                        if (!context.mounted) return;
                                        setState(() {});
                                      },
                                icon: const Icon(Icons.usb),
                                label: const Text('Hardware Setup'),
                              ),
                            ],
                          ),
                          if (cardStatusMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              cardStatusMessage!,
                              style: TextStyle(
                                color: cardStatusMessage!.toLowerCase().contains('approved')
                                    ? Colors.green[800]
                                    : Colors.red[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessingCard ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm
                    ? () async {
                        if (selectedMethod == 'card') {
                          await processCardPayment();
                          return;
                        }

                        Navigator.pop(context, {
                          'payment_method': selectedMethod,
                          'amount_tendered': amountTendered,
                          'change_amount': changeAmount,
                        });
                      }
                    : null,
                child: Text(
                  selectedMethod == 'card' ? 'Confirm Card Payment' : 'Confirm Payment',
                ),
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
