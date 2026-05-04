import 'package:flutter/material.dart';

import '../services/card_terminal_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import 'app_snackbar.dart';
import 'premium_dialog.dart';

Future<void> showHardwareSetupDialog(BuildContext context) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final successColor = const Color(0xFF1FCF9A);
  final successSoft = successColor.withOpacity(isDark ? 0.18 : 0.12);
  final warningColor = const Color(0xFFFFB65C);
  final dangerColor = const Color(0xFFFF6B7A);

  void showInfoMessage(String message, {Color? backgroundColor}) {
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: backgroundColor,
    );
  }

  final cardTerminal = CardTerminalService.instance;
  final printer = ReceiptPrinterService.instance;

  final initialPorts = cardTerminal.getAvailablePorts();
  final initialPrinters = await printer.getInstalledPrinters();

  if (!context.mounted) return;

  await showPremiumDialog<void>(
    context: context,
    builder: (context) {
      var ports = List<String>.from(initialPorts);
      var printers = List<String>.from(initialPrinters);
      var selectedBaudRate = cardTerminal.baudRate;
      var isBusy = false;

      Future<void> refreshLists(StateSetter setState) async {
        setState(() {
          isBusy = true;
        });

        final nextPrinters = await printer.getInstalledPrinters();

        if (!context.mounted) return;

        setState(() {
          ports = cardTerminal.getAvailablePorts();
          printers = nextPrinters;
          isBusy = false;
        });
      }

      Future<void> connectCardPort(String port, StateSetter setState) async {
        setState(() {
          isBusy = true;
        });

        final ok = await cardTerminal.connect(
          port,
          baudRate: selectedBaudRate,
        );

        if (!context.mounted) return;

        setState(() {
          isBusy = false;
        });

        showInfoMessage(
          ok
              ? 'Connected card terminal on $port'
              : 'Failed to connect card terminal on $port',
          backgroundColor: ok ? successColor : dangerColor,
        );
      }

      Future<void> selectPrinter(
        String printerName,
        StateSetter setState,
      ) async {
        setState(() {
          isBusy = true;
        });

        final ok = await printer.selectPrinter(printerName);

        if (!context.mounted) return;

        setState(() {
          isBusy = false;
        });

        showInfoMessage(
          ok
              ? 'Receipt printer set to $printerName'
              : 'Could not set printer $printerName',
          backgroundColor: ok ? successColor : dangerColor,
        );
      }

      Future<void> runTestPrint(StateSetter setState) async {
        setState(() {
          isBusy = true;
        });

        final response = await printer.printTestSlip();

        if (!context.mounted) return;

        setState(() {
          isBusy = false;
        });

        showInfoMessage(
          response.message,
          backgroundColor: response.isSuccess ? successColor : dangerColor,
        );
      }

      Future<void> saveTestPdf(StateSetter setState) async {
        setState(() {
          isBusy = true;
        });

        final response = await ReceiptPdfService.instance.saveReceiptPdf(
          transactionId: 0,
          cashierName: 'Hardware Test',
          paymentMethod: 'cash',
          items: const [
            {
              'name': 'Printer Test Item',
              'qty': 1,
              'unitPrice': 0.0,
              'lineTotal': 0.0,
            },
          ],
          subtotal: 0.0,
          discountAmount: 0.0,
          total: 0.0,
          storeName: 'FOOD CITY',
          storeAddress: 'Windows PDF Test',
          storePhone: '',
          footerNote: 'If you can read this, PDF receipt export works.',
        );

        if (!context.mounted) return;

        setState(() {
          isBusy = false;
        });

        showInfoMessage(
          response.message,
          backgroundColor: response.isSuccess ? successColor : dangerColor,
        );
      }

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Hardware Setup'),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Card Terminal',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (cardTerminal.isConnected)
                          Chip(
                            label: Text(
                              cardTerminal.connectedPortName ?? 'Connected',
                            ),
                            backgroundColor: successSoft,
                            side: BorderSide(color: successColor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Baud rate:',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: selectedBaudRate,
                          items: const [9600, 19200, 38400, 57600, 115200]
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: isBusy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    selectedBaudRate = value;
                                  });
                                },
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => refreshLists(setState),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (ports.isEmpty)
                      Text(
                        'No COM ports found. Connect the terminal, then refresh.',
                        style: TextStyle(color: dangerColor),
                      )
                    else
                      ...ports.map(
                        (port) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(port),
                          subtitle: Text(
                            port == cardTerminal.connectedPortName
                                ? 'Currently connected'
                                : 'Available serial port',
                          ),
                          trailing: port == cardTerminal.connectedPortName
                              ? OutlinedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () async {
                                          setState(() {
                                            isBusy = true;
                                          });
                                          await cardTerminal.disconnect(
                                            clearSaved: true,
                                          );
                                          if (!context.mounted) return;
                                          setState(() {
                                            isBusy = false;
                                          });
                                          showInfoMessage(
                                            'Card terminal disconnected.',
                                            backgroundColor: warningColor,
                                          );
                                        },
                                  child: const Text('Disconnect'),
                                )
                              : ElevatedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => connectCardPort(port, setState),
                                  child: const Text('Connect'),
                                ),
                        ),
                      ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Receipt Printer',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (printer.isConnected)
                          Chip(
                            label: Text(
                              printer.connectedPrinterName ?? 'Selected',
                            ),
                            backgroundColor: successSoft,
                            side: BorderSide(color: successColor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (printers.isEmpty)
                      Text(
                        'No Windows printers found. Install or share the receipt printer first.',
                        style: TextStyle(color: dangerColor),
                      )
                    else
                      ...printers.map(
                        (printerName) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(printerName),
                          subtitle: Text(
                            printerName == printer.connectedPrinterName
                                ? 'Currently selected printer'
                                : 'Installed Windows printer',
                          ),
                          trailing: printerName == printer.connectedPrinterName
                              ? OutlinedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () async {
                                          setState(() {
                                            isBusy = true;
                                          });
                                          await printer.disconnect(
                                            clearSaved: true,
                                          );
                                          if (!context.mounted) return;
                                          setState(() {
                                            isBusy = false;
                                          });
                                          showInfoMessage(
                                            'Receipt printer cleared.',
                                            backgroundColor: warningColor,
                                          );
                                        },
                                  child: const Text('Clear'),
                                )
                              : ElevatedButton(
                                  onPressed: isBusy
                                      ? null
                                      : () => selectPrinter(
                                            printerName,
                                            setState,
                                          ),
                                  child: const Text('Use'),
                                ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (printer.isConnected)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: isBusy
                                  ? null
                                  : () => runTestPrint(setState),
                              icon: const Icon(Icons.print),
                              label: const Text('Print Test Slip'),
                            ),
                            OutlinedButton.icon(
                              onPressed: isBusy
                                  ? null
                                  : () => saveTestPdf(setState),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Save Test PDF'),
                            ),
                          ],
                        ),
                      ),
                    if (!printer.isConnected)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => saveTestPdf(setState),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Save Test PDF'),
                        ),
                      ),
                    if (isBusy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}
