import 'package:flutter/material.dart';

import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../services/purchase_order_service.dart';
import 'purchase_order_receive_history_screen.dart';

class PurchaseOrderReceiveScreen extends StatefulWidget {
  const PurchaseOrderReceiveScreen({
    super.key,
    required this.purchaseOrder,
    required this.cashierName,
  });

  final PurchaseOrder purchaseOrder;
  final String cashierName;

  @override
  State<PurchaseOrderReceiveScreen> createState() =>
      _PurchaseOrderReceiveScreenState();
}

class _PurchaseOrderReceiveScreenState extends State<PurchaseOrderReceiveScreen> {
  final PurchaseOrderService _service = PurchaseOrderService();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _deliveryNoteController = TextEditingController();
  final TextEditingController _grnController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  PurchaseOrder? _order;
  List<PurchaseOrderItem> _items = const [];
  final Map<int, TextEditingController> _qtyControllers =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _invoiceController.dispose();
    _deliveryNoteController.dispose();
    _grnController.dispose();
    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
    });

    final order = await _service.getOrder(widget.purchaseOrder.id);
    final items = await _service.getOrderItems(widget.purchaseOrder.id);

    for (final controller in _qtyControllers.values) {
      controller.dispose();
    }
    _qtyControllers.clear();

    for (final item in items) {
      if (item.id != null) {
        _qtyControllers[item.id!] = TextEditingController();
      }
    }

    if (!mounted) return;

    setState(() {
      _order = order ?? widget.purchaseOrder;
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _openHistory() async {
    final order = _order ?? widget.purchaseOrder;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderReceiveHistoryScreen(
          purchaseOrder: order,
        ),
      ),
    );
    await _loadOrder();
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'draft':
        return 'Draft';
      case 'ordered':
        return 'Ordered';
      case 'partially_received':
        return 'Partially Received';
      case 'received':
        return 'Received';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'ordered':
        return Colors.blue;
      case 'partially_received':
        return Colors.orange;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'draft':
      default:
        return Colors.deepPurple;
    }
  }

  int _outstandingQty(PurchaseOrderItem item) {
    final remaining = item.quantity - item.receivedQuantity;
    return remaining < 0 ? 0 : remaining;
  }

  int _parsedQty(PurchaseOrderItem item) {
    if (item.id == null) return 0;
    return int.tryParse(_qtyControllers[item.id!]!.text.trim()) ?? 0;
  }

  int get _totalReceiveUnits =>
      _items.fold<int>(0, (sum, item) => sum + _parsedQty(item));

  double get _totalReceiveCost => _items.fold<double>(
        0,
        (sum, item) => sum + (_parsedQty(item) * item.unitCost),
      );

  String? _buildValidationMessage(PurchaseOrder order) {
    final validation = _service.validateReceiveAttempt(
      order: order,
      lines: _items
          .map(
            (item) => PurchaseOrderReceiveLineInput(
              barcode: item.barcode,
              productName: item.productName,
              orderedQuantity: item.quantity,
              alreadyReceivedQuantity: item.receivedQuantity,
              quantityToReceive: _parsedQty(item),
              unitCost: item.unitCost,
            ),
          )
          .toList(),
    );
    return validation;
  }

  Future<void> _submit() async {
    final order = _order;
    if (order == null) return;

    final receiveMap = <int, int>{};
    for (final item in _items) {
      if (item.id == null) continue;
      final qty = _parsedQty(item);
      if (qty > 0) {
        receiveMap[item.id!] = qty;
      }
    }

    final validationMessage = _buildValidationMessage(order);
    if (validationMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationMessage),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final result = await _service.receiveAgainstOrder(
      order: order,
      items: _items,
      receiveQuantities: receiveMap,
      cashierName: widget.cashierName,
      referenceNote: _referenceController.text.trim(),
      invoiceNumber: _invoiceController.text.trim(),
      deliveryNoteNumber: _deliveryNoteController.text.trim(),
      grnReference: _grnController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    final success = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((result['message'] ?? 'Done').toString()),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );

    if (success) {
      _referenceController.clear();
      _invoiceController.clear();
      _deliveryNoteController.clear();
      _grnController.clear();
      await _loadOrder();
    }
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusInfoCard(PurchaseOrder order) {
    final canReceive = order.canReceive;
    final backgroundColor = canReceive
        ? Colors.blue.withOpacity(0.06)
        : Colors.red.withOpacity(0.06);
    final borderColor = canReceive
        ? Colors.blue.withOpacity(0.18)
        : Colors.red.withOpacity(0.18);
    final textColor = canReceive ? Colors.blue[800]! : Colors.red[800]!;

    final message = switch (order.status) {
      'draft' =>
        'This PO is still Draft. Change status to Ordered before receiving.',
      'cancelled' =>
        'This PO is Cancelled and cannot be received.',
      'received' =>
        'This PO is already fully received. New receives are blocked.',
      'partially_received' =>
        'This PO has partial receipts. You can continue receiving only the remaining quantities.',
      _ => 'This PO is ready for line-by-line receiving.'
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLineCard(PurchaseOrderItem item) {
    final outstanding = _outstandingQty(item);
    final receiveController =
        item.id == null ? null : _qtyControllers[item.id!];
    final parsedQty = _parsedQty(item);
    final overReceive = parsedQty > outstanding && outstanding > 0;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Barcode: ${item.barcode}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('Ordered: ${item.quantity}', Colors.indigo),
                _pill('Received: ${item.receivedQuantity}', Colors.green),
                _pill('Outstanding: $outstanding', Colors.orange),
                _pill(
                  'Unit Cost: Rs. ${item.unitCost.toStringAsFixed(2)}',
                  Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (outstanding <= 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Fully received',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: receiveController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Receive Qty',
                        border: const OutlineInputBorder(),
                        errorText: overReceive
                            ? 'Cannot exceed outstanding $outstanding'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () {
                        receiveController?.text = outstanding.toString();
                        setState(() {});
                      },
                      child: const Text('Full'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () {
                        receiveController?.clear();
                        setState(() {});
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            if (outstanding > 0 && parsedQty > 0) ...[
              const SizedBox(height: 10),
              Text(
                'This receive total: Rs. ${(parsedQty * item.unitCost).toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: overReceive ? Colors.red : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final order = _order ?? widget.purchaseOrder;
    final statusColor = _statusColor(order.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Receive • ${order.orderNumber}'),
        actions: [
          IconButton(
            tooltip: 'Receive history',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Refresh order',
            onPressed: _loadOrder,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _isLoading || _isSaving ? null : _submit,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.inventory_2_outlined),
            label: Text(_isSaving ? 'Receiving...' : 'Receive Against PO'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOrder,
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
                          Text(
                            order.supplierName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'PO: ${order.orderNumber}',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(order.status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (order.referenceNote.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Reference: ${order.referenceNote}',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildStatusInfoCard(order),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(
                            value: order.receiveProgress,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Received ${order.receivedUnits} of ${order.totalUnits} unit(s)',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSummaryCard(
                          label: 'Outstanding',
                          value: order.outstandingUnits.toString(),
                          icon: Icons.pending_actions,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        _buildSummaryCard(
                          label: 'Receive Now',
                          value: _totalReceiveUnits.toString(),
                          icon: Icons.playlist_add_check,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 10),
                        _buildSummaryCard(
                          label: 'Current Receive Cost',
                          value: 'Rs. ${_totalReceiveCost.toStringAsFixed(2)}',
                          icon: Icons.payments_outlined,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referenceController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Receive Reference Note (Optional)',
                      hintText: 'Delivery note, invoice no, remarks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _invoiceController,
                          decoration: const InputDecoration(
                            labelText: 'Invoice No',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _deliveryNoteController,
                          decoration: const InputDecoration(
                            labelText: 'Delivery Note',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _grnController,
                    decoration: const InputDecoration(
                      labelText: 'GRN / Delivery Ref (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Any posted receipt batch can later be reviewed or reversed from Receive History with manager approval.',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'PO Line Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No PO items found.')),
                      ),
                    )
                  else
                    ..._items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildLineCard(item),
                        )),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}
