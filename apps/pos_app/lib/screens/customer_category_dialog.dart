import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class CustomerCategoryDialogResult {
  const CustomerCategoryDialogResult({
    required this.name,
    this.description,
    this.defaultPricingSchemeId,
    this.isActive = true,
  });

  final String name;
  final String? description;
  final int? defaultPricingSchemeId;
  final bool isActive;
}

Future<CustomerCategoryDialogResult?> showCustomerCategoryDialog({
  required BuildContext context,
  CustomerCategory? category,
  List<PricingScheme> schemes = const [],
}) {
  return showPremiumDialog<CustomerCategoryDialogResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        _CustomerCategoryDialog(category: category, schemes: schemes),
  );
}

class _CustomerCategoryDialog extends StatefulWidget {
  const _CustomerCategoryDialog({this.category, required this.schemes});

  final CustomerCategory? category;
  final List<PricingScheme> schemes;

  @override
  State<_CustomerCategoryDialog> createState() =>
      _CustomerCategoryDialogState();
}

class _CustomerCategoryDialogState extends State<_CustomerCategoryDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late bool _isActive;
  int? _defaultPricingSchemeId;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _danger = Color(0xFFFF6B7A);

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _descriptionController = TextEditingController(
      text: category?.description ?? '',
    );
    _isActive = category?.isActive ?? true;
    _defaultPricingSchemeId = category?.defaultPricingSchemeId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.category != null;

  void _showMessage(String message) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: _danger);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Category name is required.');
      return;
    }

    Navigator.of(context).pop(
      CustomerCategoryDialogResult(
        name: name,
        description: _descriptionController.text.trim(),
        defaultPricingSchemeId: _defaultPricingSchemeId,
        isActive: _isActive,
      ),
    );
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
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
                      border: Border.all(color: _brand.withValues(alpha: 0.24)),
                    ),
                    child: const Icon(
                      Icons.groups_2_rounded,
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
                          _isEdit ? 'Edit Category' : 'Add Category',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Group customers and assign an optional default scheme.',
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
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  label: 'Category name *',
                  icon: Icons.label_rounded,
                  hint: 'Hotel / Restaurant / Dealer',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: _inputDecoration(
                  label: 'Description',
                  icon: Icons.notes_rounded,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int?>(
                initialValue: _defaultPricingSchemeId,
                decoration: _inputDecoration(
                  label: 'Default pricing scheme',
                  icon: Icons.sell_rounded,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('No default scheme'),
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
                    _defaultPricingSchemeId = value;
                  });
                },
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: panelSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: SwitchListTile(
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _brand,
                  title: Text(
                    'Active',
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    _isActive
                        ? 'Category can be assigned to customers.'
                        : 'Category stays saved but is inactive.',
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
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
                    onPressed: _submit,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_isEdit ? 'Save Category' : 'Add Category'),
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
