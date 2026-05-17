import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../widgets/premium_dialog.dart';

class CustomerCategoryAssignmentResult {
  const CustomerCategoryAssignmentResult({
    this.customerCategoryId,
    this.pricingSchemeId,
  });

  final int? customerCategoryId;
  final int? pricingSchemeId;
}

Future<CustomerCategoryAssignmentResult?> showCustomerCategoryAssignmentDialog({
  required BuildContext context,
  required Customer customer,
  required List<CustomerCategory> categories,
  required List<PricingScheme> schemes,
}) {
  return showPremiumDialog<CustomerCategoryAssignmentResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CustomerCategoryAssignmentDialog(
      customer: customer,
      categories: categories,
      schemes: schemes,
    ),
  );
}

class _CustomerCategoryAssignmentDialog extends StatefulWidget {
  const _CustomerCategoryAssignmentDialog({
    required this.customer,
    required this.categories,
    required this.schemes,
  });

  final Customer customer;
  final List<CustomerCategory> categories;
  final List<PricingScheme> schemes;

  @override
  State<_CustomerCategoryAssignmentDialog> createState() =>
      _CustomerCategoryAssignmentDialogState();
}

class _CustomerCategoryAssignmentDialogState
    extends State<_CustomerCategoryAssignmentDialog> {
  int? _customerCategoryId;
  int? _pricingSchemeId;

  static const Color _brand = Color(0xFF2AAA8A);

  @override
  void initState() {
    super.initState();
    _customerCategoryId = widget.customer.customerCategoryId;
    _pricingSchemeId = widget.customer.pricingSchemeId;
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);

    return InputDecoration(
      labelText: label,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF0F1C31) : Colors.white;
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
    final textPrimary = isDark
        ? const Color(0xFFF4F8FF)
        : const Color(0xFF14263B);
    final textSecondary = isDark
        ? const Color(0xFF9DB0C8)
        : const Color(0xFF667A92);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _brand.withValues(alpha: isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.account_tree_rounded,
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
                          'Category & Scheme',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.customer.displayName,
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
              const SizedBox(height: 20),
              DropdownButtonFormField<int?>(
                initialValue: _customerCategoryId,
                decoration: _inputDecoration(
                  label: 'Customer category',
                  icon: Icons.groups_2_rounded,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No category'),
                  ),
                  ...widget.categories.map(
                    (category) => DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(
                        category.isActive
                            ? category.displayName
                            : '${category.displayName} (inactive)',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _customerCategoryId = value;
                  });
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int?>(
                initialValue: _pricingSchemeId,
                decoration: _inputDecoration(
                  label: 'Direct pricing scheme',
                  icon: Icons.sell_rounded,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Use category default'),
                  ),
                  const DropdownMenuItem<int?>(
                    value: 0,
                    child: Text('No Scheme'),
                  ),
                  ...widget.schemes.map(
                    (scheme) => DropdownMenuItem<int?>(
                      value: scheme.id,
                      child: Text(
                        scheme.isActive
                            ? scheme.displayName
                            : '${scheme.displayName} (inactive)',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _pricingSchemeId = value;
                  });
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(
                        CustomerCategoryAssignmentResult(
                          customerCategoryId: _customerCategoryId,
                          pricingSchemeId: _pricingSchemeId,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Assignment'),
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
