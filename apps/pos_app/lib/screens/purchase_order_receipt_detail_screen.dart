import 'package:flutter/material.dart';

import '../models/purchase_order_receipt.dart';
import '../services/purchase_order_service.dart';

class PurchaseOrderReceiptDetailScreen extends StatefulWidget {
  final int receiptId;
  final int purchaseOrderId;

  const PurchaseOrderReceiptDetailScreen({
    super.key,
    required this.receiptId,
    required this.purchaseOrderId,
  });

  @override
  State<PurchaseOrderReceiptDetailScreen> createState() =>
      _PurchaseOrderReceiptDetailScreenState();
}

class _PurchaseOrderReceiptDetailScreenState
    extends State<PurchaseOrderReceiptDetailScreen> {
  final PurchaseOrderService _service = PurchaseOrderService();
  PurchaseOrderReceipt? _receipt;
  bool _loading = true;
  bool _reversing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _service.getReceiptById(widget.receiptId);
    if (!mounted) return;
    setState(() {
      _receipt = result;
      _loading = false;
    });
  }

  Future<void> _reverse() async {
    final receipt = _receipt;
    if (receipt == null || receipt.isReversed) return;

    final reasonController = TextEditingController();
    final managerController = TextEditingController();
    final cashierController = TextEditingController();

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Reverse Receipt Batch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This creates an audit trail and marks the receipt batch reversed. Use only for receiving mistakes.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: managerController,
                    decoration: const InputDecoration(
                      labelText: 'Manager Name / Approval',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cashierController,
                    decoration: const InputDecoration(
                      labelText: 'Reversed By',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (reasonController.text.trim().isEmpty ||
                      managerController.text.trim().isEmpty ||
                      cashierController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Reason, manager approval, and reversed by are required.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Approve Reverse'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _reversing = true);
    try {
      await _service.reverseReceiptBatch(
        ReversePurchaseOrderReceiptRequest(
          receiptId: receipt.id,
          purchaseOrderId: receipt.purchaseOrderId,
          reason: reasonController.text.trim(),
          cashierName: cashierController.text.trim(),
          managerName: managerController.text.trim(),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt batch reversed and audited.'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _reversing = false);
      }
    }
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Batch Detail'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : receipt == null
              ? const Center(child: Text('Receipt batch not found.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              receipt.poNumber,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _pill('Units: ${receipt.totalUnits}', Colors.blue),
                                _pill('Lines: ${receipt.totalLines}', Colors.green),
                                _pill(
                                  receipt.isReversed ? 'Reversed' : 'Active',
                                  receipt.isReversed ? Colors.red : Colors.orange,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('Supplier: ${receipt.supplierName}'),
                            Text('Received At: ${receipt.receivedAt}'),
                            if (receipt.invoiceNumber.isNotEmpty)
                              Text('Invoice: ${receipt.invoiceNumber}'),
                            if (receipt.deliveryNoteNumber.isNotEmpty)
                              Text('Delivery Note: ${receipt.deliveryNoteNumber}'),
                            if (receipt.grnReference.isNotEmpty)
                              Text('GRN Ref: ${receipt.grnReference}'),
                            if (receipt.reversalReason.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Reversal Reason: ${receipt.reversalReason}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Received Lines',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    ...receipt.lines.map(
                      (line) => Card(
                        child: ListTile(
                          title: Text(
                            line.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Barcode: ${line.barcode}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Qty: ${line.receivedQuantity}'),
                              Text('Rs. ${line.lineTotal.toStringAsFixed(2)}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: receipt.isReversed || _reversing ? null : _reverse,
                      icon: _reversing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.undo),
                      label: Text(
                        _reversing ? 'Reversing...' : 'Reverse Receipt Batch',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ],
                ),
    );
  }
}
