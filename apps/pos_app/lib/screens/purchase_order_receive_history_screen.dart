import 'package:flutter/material.dart';

import '../models/purchase_order.dart';
import '../models/purchase_order_receipt.dart';
import '../services/purchase_order_service.dart';

class PurchaseOrderReceiveHistoryScreen extends StatefulWidget {
  const PurchaseOrderReceiveHistoryScreen({
    super.key,
    this.purchaseOrder,
  });

  final PurchaseOrder? purchaseOrder;

  @override
  State<PurchaseOrderReceiveHistoryScreen> createState() =>
      _PurchaseOrderReceiveHistoryScreenState();
}

class _PurchaseOrderReceiveHistoryScreenState
    extends State<PurchaseOrderReceiveHistoryScreen> {
  final PurchaseOrderService _service = PurchaseOrderService();

  bool _isLoading = true;
  List<PurchaseOrderReceipt> _receipts = const [];
  final Map<int, List<PurchaseOrderReceiptLine>> _linesByReceipt = {};
  final Set<int> _loadingLineIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _isLoading = true;
    });

    final receipts = await _service.getReceipts(
      purchaseOrderId: widget.purchaseOrder?.id,
    );

    if (!mounted) return;
    setState(() {
      _receipts = receipts;
      _isLoading = false;
    });
  }

  Future<void> _loadLines(int receiptId) async {
    if (_linesByReceipt.containsKey(receiptId) || _loadingLineIds.contains(receiptId)) {
      return;
    }

    setState(() {
      _loadingLineIds.add(receiptId);
    });

    final lines = await _service.getReceiptLines(receiptId);

    if (!mounted) return;
    setState(() {
      _loadingLineIds.remove(receiptId);
      _linesByReceipt[receiptId] = lines;
    });
  }

  String _formatDateTime(String value) {
    if (value.trim().isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$date  $hour:$minute $period';
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildReceiptCard(PurchaseOrderReceipt receipt) {
    final lines = _linesByReceipt[receipt.id];
    final isLoadingLines = _loadingLineIds.contains(receipt.id);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _loadLines(receipt.id);
            }
          },
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                receipt.purchaseOrderNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                receipt.supplierName,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('Lines: ${receipt.totalLines}', Colors.indigo),
                    _pill('Units: ${receipt.totalUnits}', Colors.blue),
                    _pill(
                      'Cost: Rs. ${receipt.totalCost.toStringAsFixed(2)}',
                      Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Received by ${receipt.cashierName.isEmpty ? 'Unknown' : receipt.cashierName} • ${_formatDateTime(receipt.createdAt)}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
                ),
                if (receipt.referenceNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reference: ${receipt.referenceNote}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
          children: [
            if (isLoadingLines)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (lines == null || lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No receipt lines found.'),
              )
            else
              ...lines.map(
                (line) => Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Barcode: ${line.barcode}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill('Qty: ${line.quantity}', Colors.orange),
                          _pill(
                            'Unit: Rs. ${line.unitCost.toStringAsFixed(2)}',
                            Colors.blueGrey,
                          ),
                          _pill(
                            'Line: Rs. ${line.lineCost.toStringAsFixed(2)}',
                            Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.purchaseOrder == null
        ? 'PO Receive History'
        : 'Receive History • ${widget.purchaseOrder!.orderNumber}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _loadReceipts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReceipts,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Purchase Order Receive History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.purchaseOrder == null
                          ? 'Review all local receipt batches created from purchase order receiving in POS_APP.'
                          : 'Review local receipt batches created for this purchase order.',
                      style: TextStyle(color: Colors.grey[700], height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_receipts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text('No PO receipt history found yet.'),
                  ),
                ),
              )
            else
              ..._receipts.map(
                (receipt) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildReceiptCard(receipt),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
