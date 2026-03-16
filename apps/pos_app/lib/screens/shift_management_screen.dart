import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class ShiftManagementScreen extends StatefulWidget {
  final String cashierName;

  const ShiftManagementScreen({
    super.key,
    required this.cashierName,
  });

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  Map<String, dynamic>? _openShiftSummary;

  final TextEditingController _openingCashController =
      TextEditingController(text: '0.00');
  final TextEditingController _closingCashController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadShift();
  }

  @override
  void dispose() {
    _openingCashController.dispose();
    _closingCashController.dispose();
    super.dispose();
  }

  Future<void> _loadShift() async {
    setState(() {
      _isLoading = true;
    });

    final summary = await DatabaseHelper.instance.getOpenShiftSummaryForCashier(
      widget.cashierName,
    );

    if (!mounted) return;

    setState(() {
      _openShiftSummary = summary;
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

  Widget _statCard(String label, String value, {Color? valueColor}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShift() async {
    if (_isSubmitting) return;

    final openingCash =
        double.tryParse(_openingCashController.text.trim()) ?? -1;

    if (openingCash < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid opening cash amount.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await DatabaseHelper.instance.openShift(
        cashierName: widget.cashierName,
        openingCash: openingCash,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift opened successfully.'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadShift();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _closeShift() async {
    if (_isSubmitting || _openShiftSummary == null) return;

    final closingCash =
        double.tryParse(_closingCashController.text.trim()) ?? -1;

    if (closingCash < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid closing cash amount.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final closedSummary = await DatabaseHelper.instance.closeShift(
        shiftId: (_openShiftSummary!['id'] as num).toInt(),
        cashierName: widget.cashierName,
        closingCash: closingCash,
      );

      if (!mounted) return;

      final expectedCash =
          ((closedSummary['expected_cash'] as num?) ?? 0).toDouble();
      final variance = ((closedSummary['variance'] as num?) ?? 0).toDouble();

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Shift Closed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Expected Cash: Rs. ${expectedCash.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              Text('Counted Cash: Rs. ${closingCash.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              Text(
                'Variance: Rs. ${variance.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: variance == 0
                      ? Colors.black87
                      : (variance > 0 ? Colors.green : Colors.red),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = _openShiftSummary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Management'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : shift == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'No Open Shift',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text('Cashier: ${widget.cashierName}'),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _openingCashController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Opening Cash',
                                  prefixText: 'Rs. ',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _isSubmitting ? null : _openShift,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  _isSubmitting
                                      ? 'OPENING...'
                                      : 'OPEN SHIFT',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadShift,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Shift',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text('Cashier: ${widget.cashierName}'),
                              const SizedBox(height: 4),
                              Text(
                                'Opened: ${_formatDateTime((shift['opened_at'] ?? '').toString())}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Opening Cash: Rs. ${(((shift['opening_cash'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 2.2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        children: [
                          _statCard(
                            'Cash Sales',
                            'Rs. ${(((shift['cash_sales_total'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                            valueColor: Colors.green,
                          ),
                          _statCard(
                            'Card Sales',
                            'Rs. ${(((shift['card_sales_total'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                            valueColor: Colors.blue,
                          ),
                          _statCard(
                            'Cash Refunds',
                            'Rs. ${(((shift['cash_refund_total'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                            valueColor: Colors.red,
                          ),
                          _statCard(
                            'Expected Cash',
                            'Rs. ${(((shift['expected_cash'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                            valueColor: Colors.deepPurple,
                          ),
                          _statCard(
                            'Transactions',
                            '${((shift['transaction_count'] as num?) ?? 0).toInt()}',
                          ),
                          _statCard(
                            'Refund Count',
                            '${((shift['refund_count'] as num?) ?? 0).toInt()}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Close Shift',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _closingCashController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Counted Cash at Close',
                                  prefixText: 'Rs. ',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _isSubmitting ? null : _closeShift,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  _isSubmitting
                                      ? 'CLOSING...'
                                      : 'CLOSE SHIFT',
                                  style: const TextStyle(color: Colors.white),
                                ),
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
}