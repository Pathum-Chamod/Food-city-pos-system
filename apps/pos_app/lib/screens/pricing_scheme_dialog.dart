import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class PricingSchemeDialogResult {
  const PricingSchemeDialogResult({
    required this.name,
    this.description,
    this.isActive = true,
    this.priority = 100,
  });

  final String name;
  final String? description;
  final bool isActive;
  final int priority;
}

Future<PricingSchemeDialogResult?> showPricingSchemeDialog({
  required BuildContext context,
  PricingScheme? scheme,
  String? initialName,
  String? title,
}) {
  return showPremiumDialog<PricingSchemeDialogResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PricingSchemeDialog(
      scheme: scheme,
      initialName: initialName,
      title: title,
    ),
  );
}

class _PricingSchemeDialog extends StatefulWidget {
  const _PricingSchemeDialog({this.scheme, this.initialName, this.title});

  final PricingScheme? scheme;
  final String? initialName;
  final String? title;

  @override
  State<_PricingSchemeDialog> createState() => _PricingSchemeDialogState();
}

class _PricingSchemeDialogState extends State<_PricingSchemeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priorityController;
  late bool _isActive;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _danger = Color(0xFFFF6B7A);

  @override
  void initState() {
    super.initState();
    final scheme = widget.scheme;
    _nameController = TextEditingController(
      text: widget.initialName ?? scheme?.name ?? '',
    );
    _descriptionController = TextEditingController(
      text: scheme?.description ?? '',
    );
    _priorityController = TextEditingController(
      text: (scheme?.priority ?? 100).toString(),
    );
    _isActive = scheme?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.scheme != null;

  void _showMessage(String message) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: _danger);
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Pricing scheme name is required.');
      return;
    }

    final priority = int.tryParse(_priorityController.text.trim());
    if (priority == null) {
      _showMessage('Priority must be a whole number.');
      return;
    }

    Navigator.of(context).pop(
      PricingSchemeDialogResult(
        name: name,
        description: _descriptionController.text.trim(),
        isActive: _isActive,
        priority: priority,
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
                      Icons.sell_rounded,
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
                          widget.title ??
                              (_isEdit ? 'Edit Scheme' : 'Add Scheme'),
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reusable pricing setup for customers and categories.',
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
                  label: 'Scheme name *',
                  icon: Icons.label_rounded,
                  hint: 'Wholesale Scheme / Hotel Scheme',
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
              TextField(
                controller: _priorityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDecoration(
                  label: 'Priority',
                  icon: Icons.low_priority_rounded,
                ),
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
                        ? 'Scheme can be assigned to customers and categories.'
                        : 'Scheme stays saved but is inactive.',
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
                    label: Text(_isEdit ? 'Save Scheme' : 'Add Scheme'),
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
