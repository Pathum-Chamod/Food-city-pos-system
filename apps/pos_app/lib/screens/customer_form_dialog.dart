import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import '../services/customer_service.dart';
import '../services/pricing_scheme_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<Customer?> showCustomerFormDialog({
  required BuildContext context,
  Customer? customer,
  int? actorUserId,
}) {
  return showPremiumDialog<Customer?>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        _CustomerFormDialog(customer: customer, actorUserId: actorUserId),
  );
}

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.customer, this.actorUserId});

  final Customer? customer;
  final int? actorUserId;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late final FocusNode _phoneFocusNode;

  int? _selectedCategoryId;
  int? _selectedDirectSchemeId;
  late bool _isActive;
  bool _isSaving = false;
  bool _isLoadingPricingLookups = true;
  List<CustomerCategory> _categories = const [];
  List<PricingScheme> _schemes = const [];

  bool get _isEdit => widget.customer != null;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _warning = Color(0xFFFFB65C);

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameController = TextEditingController(text: customer?.name ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _emailController = TextEditingController(text: customer?.email ?? '');
    _addressController = TextEditingController(text: customer?.address ?? '');
    _notesController = TextEditingController(text: customer?.notes ?? '');
    _phoneFocusNode = FocusNode();
    _selectedCategoryId = customer?.customerCategoryId;
    _selectedDirectSchemeId = customer?.pricingSchemeId;
    _isActive = customer?.isActive ?? true;
    _loadPricingLookups();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSaving) return;
      _phoneFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _showMessage(String message, {Color color = _warning}) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  Future<void> _loadPricingLookups() async {
    try {
      final service = PricingSchemeService.instance;
      final results = await Future.wait([
        service.getCustomerCategories(),
        service.getPricingSchemes(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<CustomerCategory>;
        _schemes = results[1] as List<PricingScheme>;
        if (!_categories.any(
          (category) => category.id == _selectedCategoryId,
        )) {
          _selectedCategoryId = null;
        }
        if (_selectedDirectSchemeId != null &&
            _selectedDirectSchemeId! > 0 &&
            !_schemes.any((scheme) => scheme.id == _selectedDirectSchemeId)) {
          _selectedDirectSchemeId = null;
        }
        _isLoadingPricingLookups = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPricingLookups = false;
      });
      _showMessage('Could not load pricing categories.', color: _danger);
    }
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showMessage('Phone number is required.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final service = CustomerService.instance;
      if (_isEdit) {
        final customerId = widget.customer?.id ?? 0;
        await service.updateCustomer(
          id: customerId,
          name: name,
          phone: phone,
          email: _emailController.text.trim(),
          address: _addressController.text.trim(),
          customerCategoryId: _selectedCategoryId,
          pricingSchemeId: _selectedDirectSchemeId,
          notes: _notesController.text.trim(),
          isActive: _isActive,
          updatedBy: widget.actorUserId,
        );

        final updated = await service.getCustomerById(customerId);
        if (!mounted) return;
        Navigator.of(context).pop(updated);
      } else {
        final id = await service.createCustomer(
          name: name,
          phone: phone,
          email: _emailController.text.trim(),
          address: _addressController.text.trim(),
          customerCategoryId: _selectedCategoryId,
          pricingSchemeId: _selectedDirectSchemeId,
          notes: _notesController.text.trim(),
          createdBy: widget.actorUserId,
        );

        final created = await service.getCustomerById(id);
        if (!mounted) return;
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      final message = e.toString().replaceFirst('Exception: ', '');
      _showMessage(message, color: _danger);
    }
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

  Widget _sectionTitle(String text, Color textPrimary) {
    return Text(
      text,
      style: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w900,
        fontSize: 14,
      ),
    );
  }

  Widget _sectionPanel({
    required String title,
    required IconData icon,
    required Color panelSoft,
    required Color border,
    required Color textPrimary,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _brand, size: 20),
              const SizedBox(width: 8),
              _sectionTitle(title, textPrimary),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  CustomerCategory? get _selectedCategory {
    for (final category in _categories) {
      if (category.id == _selectedCategoryId) return category;
    }
    return null;
  }

  PricingScheme? _schemeById(int? id) {
    if (id == null) return null;
    for (final scheme in _schemes) {
      if (scheme.id == id) return scheme;
    }
    return null;
  }

  String _categoryLabel(CustomerCategory category) {
    return category.isActive
        ? category.displayName
        : '${category.displayName} (inactive)';
  }

  String _schemeLabel(PricingScheme scheme) {
    return scheme.isActive
        ? scheme.displayName
        : '${scheme.displayName} (inactive)';
  }

  Widget _pricingSummaryTile({
    required Color panelSoft,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final category = _selectedCategory;
    final directScheme = _schemeById(_selectedDirectSchemeId);
    final inheritedScheme = _schemeById(category?.defaultPricingSchemeId);
    final noSchemeSelected = _selectedDirectSchemeId == 0;

    final title = noSchemeSelected
        ? 'No pricing scheme'
        : directScheme != null
        ? directScheme.displayName
        : inheritedScheme != null
        ? inheritedScheme.displayName
        : 'No pricing scheme';

    final subtitle = noSchemeSelected
        ? 'Direct customer setting disables category pricing scheme.'
        : directScheme != null
        ? 'Direct customer scheme'
        : inheritedScheme != null
        ? 'Inherited from ${category?.displayName ?? 'category'}'
        : category == null
        ? 'Choose a category to inherit its default pricing scheme.'
        : '${category.displayName} has no default pricing scheme.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.24)),
            ),
            child: const Icon(Icons.price_check_rounded, color: _brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final availableHeight = MediaQuery.of(context).size.height - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: availableHeight < 420 ? 420 : availableHeight,
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
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Icons.person_add_alt_1_rounded,
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
                          _isEdit ? 'Edit Customer' : 'Add Customer',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isEdit
                              ? '${widget.customer!.displayCode} • Update customer details'
                              : 'Create a customer profile and attach it to sales.',
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionPanel(
                        title: 'Customer',
                        icon: Icons.person_rounded,
                        panelSoft: panelSoft,
                        border: border,
                        textPrimary: textPrimary,
                        children: [
                          TextField(
                            controller: _phoneController,
                            focusNode: _phoneFocusNode,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9+\-\s()]'),
                              ),
                            ],
                            decoration: _inputDecoration(
                              label: 'Phone number *',
                              icon: Icons.phone_rounded,
                              hint: 'Example: 0712345678',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'Customer name',
                              icon: Icons.person_rounded,
                              hint: 'Optional',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionPanel(
                        title: 'Pricing',
                        icon: Icons.price_change_rounded,
                        panelSoft: panelSoft,
                        border: border,
                        textPrimary: textPrimary,
                        children: _isLoadingPricingLookups
                            ? [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Loading categories and schemes...',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ]
                            : [
                                DropdownButtonFormField<int?>(
                                  initialValue: _selectedCategoryId,
                                  decoration: _inputDecoration(
                                    label: 'Customer category',
                                    icon: Icons.groups_rounded,
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('No category'),
                                    ),
                                    ..._categories.map(
                                      (category) => DropdownMenuItem<int?>(
                                        value: category.id,
                                        child: Text(_categoryLabel(category)),
                                      ),
                                    ),
                                  ],
                                  onChanged: _isSaving
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedCategoryId = value;
                                          });
                                        },
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<int?>(
                                  initialValue: _selectedDirectSchemeId,
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
                                    ..._schemes.map(
                                      (scheme) => DropdownMenuItem<int?>(
                                        value: scheme.id,
                                        child: Text(_schemeLabel(scheme)),
                                      ),
                                    ),
                                  ],
                                  onChanged: _isSaving
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedDirectSchemeId = value;
                                          });
                                        },
                                ),
                                const SizedBox(height: 12),
                                _pricingSummaryTile(
                                  panelSoft: panel,
                                  border: border,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                              ],
                      ),
                      const SizedBox(height: 14),
                      _sectionPanel(
                        title: 'Contact Notes',
                        icon: Icons.contact_page_rounded,
                        panelSoft: panelSoft,
                        border: border,
                        textPrimary: textPrimary,
                        children: [
                          TextField(
                            controller: _emailController,
                            enabled: !_isSaving,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'Email',
                              icon: Icons.email_rounded,
                              hint: 'Optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _addressController,
                            enabled: !_isSaving,
                            minLines: 1,
                            maxLines: 2,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'Address',
                              icon: Icons.location_on_rounded,
                              hint: 'Optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesController,
                            enabled: !_isSaving,
                            minLines: 2,
                            maxLines: 4,
                            decoration: _inputDecoration(
                              label: 'Notes',
                              icon: Icons.note_alt_rounded,
                              hint: 'Optional customer notes',
                            ),
                          ),
                        ],
                      ),
                      if (_isEdit) ...[
                        const SizedBox(height: 14),
                        _sectionPanel(
                          title: 'Status',
                          icon: Icons.verified_user_rounded,
                          panelSoft: panelSoft,
                          border: border,
                          textPrimary: textPrimary,
                          children: [
                            SwitchListTile(
                              value: _isActive,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Active customer',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                _isActive
                                    ? 'Customer can be selected during checkout.'
                                    : 'Customer is hidden from normal picker.',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              activeThumbColor: _brand,
                              inactiveThumbColor: _danger,
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _isActive = value;
                                      });
                                    },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isEdit
                                  ? Icons.save_rounded
                                  : Icons.person_add_rounded,
                            ),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : _isEdit
                            ? 'Save Changes'
                            : 'Add Customer',
                      ),
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
