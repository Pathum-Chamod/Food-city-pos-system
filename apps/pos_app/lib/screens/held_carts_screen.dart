import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class HeldCartsScreen extends StatefulWidget {
  final String cashierName;

  const HeldCartsScreen({
    super.key,
    required this.cashierName,
  });

  @override
  State<HeldCartsScreen> createState() => _HeldCartsScreenState();
}

class _HeldCartsScreenState extends State<HeldCartsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _heldCarts = [];

  @override
  void initState() {
    super.initState();
    _loadHeldCarts();
  }

  Future<void> _loadHeldCarts() async {
    setState(() {
      _isLoading = true;
    });

    final carts =
        await DatabaseHelper.instance.getHeldCartsForCashier(widget.cashierName);

    if (!mounted) return;

    setState(() {
      _heldCarts = carts;
      _isLoading = false;
    });
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _resumeHeldCart(int heldCartId) async {
    final restored = await DatabaseHelper.instance.resumeHeldCart(
      heldCartId,
      cashierName: widget.cashierName,
    );

    if (!mounted) return;

    if (restored == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Held cart not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(context, restored);
  }

  Future<void> _deleteHeldCart(int heldCartId) async {
    await DatabaseHelper.instance.deleteHeldCart(
      heldCartId,
      cashierName: widget.cashierName,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Held cart deleted.'),
        backgroundColor: Colors.green,
      ),
    );

    _loadHeldCarts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Held Carts'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _heldCarts.isEmpty
              ? const Center(child: Text('No held carts'))
              : RefreshIndicator(
                  onRefresh: _loadHeldCarts,
                  child: ListView.builder(
                    itemCount: _heldCarts.length,
                    itemBuilder: (context, index) {
                      final cart = _heldCarts[index];
                      final id = (cart['id'] as num).toInt();
                      final cartName = (cart['cart_name'] ?? 'Held Cart').toString();
                      final isRefundMode = (cart['is_refund_mode'] ?? false) == true;
                      final itemCount = (cart['item_count'] as num?)?.toInt() ?? 0;
                      final totalAmount =
                          ((cart['total_amount'] as num?) ?? 0).toDouble();
                      final updatedAt = (cart['updated_at'] ?? '').toString();

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cartName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isRefundMode
                                      ? Colors.red[50]
                                      : Colors.blue[50],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isRefundMode ? 'Refund Cart' : 'Sale Cart',
                                  style: TextStyle(
                                    color: isRefundMode
                                        ? Colors.red[700]
                                        : Colors.blue[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Items: $itemCount'),
                                const SizedBox(height: 4),
                                Text(
                                  'Total: Rs. ${totalAmount.toStringAsFixed(2)}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Saved: ${_formatDateTime(updatedAt)}',
                                ),
                              ],
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'resume') {
                                _resumeHeldCart(id);
                              } else if (value == 'delete') {
                                _deleteHeldCart(id);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'resume',
                                child: Text('Resume'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                          onTap: () => _resumeHeldCart(id),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}