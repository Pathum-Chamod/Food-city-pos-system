import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared/models/customer.dart';

import '../services/customer_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';
import 'customer_form_dialog.dart';

class CustomerPickerResult {
  const CustomerPickerResult({required this.customer, this.cleared = false});

  final Customer? customer;
  final bool cleared;
}

Future<CustomerPickerResult?> showCustomerPickerDialog({
  required BuildContext context,
  Customer? selectedCustomer,
  int? actorUserId,
  bool allowClear = true,
}) {
  return showPremiumDialog<CustomerPickerResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CustomerPickerDialog(
      selectedCustomer: selectedCustomer,
      actorUserId: actorUserId,
      allowClear: allowClear,
    ),
  );
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    this.selectedCustomer,
    this.actorUserId,
    required this.allowClear,
  });

  final Customer? selectedCustomer;
  final int? actorUserId;
  final bool allowClear;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  List<Customer> _customers = [];
  bool _isLoading = true;
  String _query = '';

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _success = Color(0xFF1FCF9A);
  static const Color _danger = Color(0xFFFF6B7A);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCustomers();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {Color color = _warning}) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final rows = await CustomerService.instance.getCustomers(
        query: _query,
        activeOnly: true,
        limit: 80,
      );

      if (!mounted) return;
      setState(() {
        _customers = rows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _isLoading = false;
      });
      _showMessage('Could not load customers.', color: _danger);
    }
  }

  void _onSearchChanged(String value) {
    _query = value.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) {
        _loadCustomers();
      }
    });
  }

  Future<void> _addNewCustomer() async {
    final created = await showCustomerFormDialog(
      context: context,
      actorUserId: widget.actorUserId,
    );

    if (!mounted || created == null) return;
    Navigator.of(context).pop(CustomerPickerResult(customer: created));
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: panelSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
    final textPrimary = isDark
        ? const Color(0xFFF4F8FF)
        : const Color(0xFF14263B);
    final textSecondary = isDark
        ? const Color(0xFF9DB0C8)
        : const Color(0xFF667A92);

    final isSelected =
        widget.selectedCustomer?.id != null &&
        widget.selectedCustomer!.id == customer.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).pop(CustomerPickerResult(customer: customer));
        },
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? _brand.withOpacity(isDark ? 0.16 : 0.10)
                : panelSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? _brand : border,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _brand.withOpacity(isDark ? 0.18 : 0.12),
                child: Text(
                  customer.displayName.trim().isEmpty
                      ? 'C'
                      : customer.displayName.trim()[0].toUpperCase(),
                  style: TextStyle(color: _brand, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          customer.displayCode,
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          customer.displayPhone,
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: isSelected ? _brand : textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final panel = isDark ? const Color(0xFF0F1C31) : Colors.white;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
    final textPrimary = isDark
        ? const Color(0xFFF4F8FF)
        : const Color(0xFF14263B);
    final textSecondary = isDark
        ? const Color(0xFF9DB0C8)
        : const Color(0xFF667A92);
    final selectedCustomer = widget.selectedCustomer;
    final availableHeight = MediaQuery.of(context).size.height - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: availableHeight < 480 ? 480 : availableHeight,
        ),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.10),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _brand.withOpacity(isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _brand.withOpacity(0.24)),
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: _brand,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Customer',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search by name, phone number, or customer code.',
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration:
                          _inputDecoration(
                            label: 'Search customer',
                            icon: Icons.search_rounded,
                            hint: 'Name / phone / code',
                          ).copyWith(
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _query = '';
                                      });
                                      _loadCustomers();
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  ),
                          ),
                      onChanged: (value) {
                        setState(() {});
                        _onSearchChanged(value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _addNewCustomer,
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Add New'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                  ),
                ],
              ),
              if (selectedCustomer != null || widget.allowClear) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panelSoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_rounded, color: _brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedCustomer == null
                              ? 'Current sale is Walk-in Customer.'
                              : 'Selected: ${selectedCustomer.displayName}',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (widget.allowClear)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(
                              const CustomerPickerResult(
                                customer: null,
                                cleared: true,
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_off_rounded),
                          label: const Text('Use Walk-in'),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: panelSoft,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_search_rounded,
                                size: 42,
                                color: textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No customers found',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add a new customer or try another search term.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: _addNewCustomer,
                                icon: const Icon(Icons.person_add_rounded),
                                label: const Text('Add New Customer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: _scrollController,
                          primary: false,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildCustomerCard(_customers[index]);
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () {
                              _showMessage(
                                'Customer list refreshed.',
                                color: _success,
                              );
                              _loadCustomers();
                            },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
