import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';

class BusinessInfoScreen extends StatefulWidget {
  const BusinessInfoScreen({super.key});

  @override
  State<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends State<BusinessInfoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchBusinessInfo();
    });
  }

  Future<void> _openEditor(BuildContext context, Map<String, dynamic> info) async {
    final storeNameController = TextEditingController(text: (info['store_name'] ?? '').toString());
    final branchNameController = TextEditingController(text: (info['branch_name'] ?? '').toString());
    final phoneController = TextEditingController(text: (info['phone_number'] ?? '').toString());
    final emailController = TextEditingController(text: (info['email'] ?? '').toString());
    final addressController = TextEditingController(text: (info['address'] ?? '').toString());
    final hoursController = TextEditingController(text: (info['business_hours'] ?? '').toString());
    final currencyController = TextEditingController(text: (info['currency_code'] ?? 'LKR').toString());
    final noteController = TextEditingController(text: (info['business_note'] ?? '').toString());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (storeNameController.text.trim().isEmpty) {
                AppSnackBar.show(
                  this.context,
                  message: 'Store name is required.',
                );
                return;
              }

              setSheetState(() => isSaving = true);
              final message =
                  await this.context.read<AdminProvider>().updateBusinessInfo(
                        storeName: storeNameController.text.trim(),
                        branchName: branchNameController.text.trim(),
                        phoneNumber: phoneController.text.trim(),
                        email: emailController.text.trim(),
                        address: addressController.text.trim(),
                        businessHours: hoursController.text.trim(),
                        currencyCode: currencyController.text.trim(),
                        businessNote: noteController.text.trim(),
                      );
              if (!mounted) return;
              setSheetState(() => isSaving = false);

              if (message == null) {
                Navigator.pop(sheetContext);
                AppSnackBar.show(
                  this.context,
                  message: 'Business info updated.',
                );
              } else {
                AppSnackBar.show(this.context, message: message);
              }
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                left: 10,
                right: 10,
                top: 10,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 10,
              ),
              child: FractionallySizedBox(
                heightFactor: 0.93,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FC),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCCD5E5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF1FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.storefront_outlined,
                                  color: Color(0xFF0F3D91),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Edit Business Info',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF172433),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Update the business details shown in the owner app.',
                                      style: TextStyle(
                                        color: Color(0xFF667085),
                                        fontWeight: FontWeight.w600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFF344054),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFDDE5F1)),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _EditorSection(
                                  title: 'Identity',
                                  subtitle: 'Core store profile details',
                                  child: Column(
                                    children: [
                                      _EditorField(
                                        label: 'Store Name',
                                        controller: storeNameController,
                                        hintText: 'Food City',
                                        icon: Icons.store_outlined,
                                      ),
                                      const SizedBox(height: 12),
                                      _EditorField(
                                        label: 'Branch Name',
                                        controller: branchNameController,
                                        hintText: 'Main Branch',
                                        icon: Icons.apartment_outlined,
                                      ),
                                      const SizedBox(height: 12),
                                      _EditorField(
                                        label: 'Currency Code',
                                        controller: currencyController,
                                        hintText: 'LKR',
                                        icon: Icons.currency_exchange_outlined,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _EditorSection(
                                  title: 'Contact',
                                  subtitle: 'How customers and staff reach you',
                                  child: Column(
                                    children: [
                                      _EditorField(
                                        label: 'Phone Number',
                                        controller: phoneController,
                                        hintText: '077 123 4567',
                                        icon: Icons.phone_outlined,
                                        keyboardType: TextInputType.phone,
                                      ),
                                      const SizedBox(height: 12),
                                      _EditorField(
                                        label: 'Email',
                                        controller: emailController,
                                        hintText: 'store@email.com',
                                        icon: Icons.alternate_email_outlined,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                      const SizedBox(height: 12),
                                      _EditorField(
                                        label: 'Address',
                                        controller: addressController,
                                        hintText: '31, Road, Sri Lanka',
                                        icon: Icons.location_on_outlined,
                                        maxLines: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _EditorSection(
                                  title: 'Operations',
                                  subtitle: 'Daily timing and notes',
                                  child: Column(
                                    children: [
                                      _EditorField(
                                        label: 'Business Hours',
                                        controller: hoursController,
                                        hintText: '8:00 AM - 10:00 PM',
                                        icon: Icons.schedule_outlined,
                                      ),
                                      const SizedBox(height: 12),
                                      _EditorField(
                                        label: 'Business Note',
                                        controller: noteController,
                                        hintText: 'Optional note',
                                        icon: Icons.sticky_note_2_outlined,
                                        maxLines: 3,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(28),
                            ),
                            border: Border(
                              top: BorderSide(color: Color(0xFFDDE5F1)),
                            ),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: isSaving ? null : submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F3D91),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                isSaving ? 'Saving...' : 'Save Business Info',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _displayValue(dynamic value, {String fallback = 'Not set yet'}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final info = provider.businessInfo;
    final isLoading = provider.isBusinessInfoLoading && info.isEmpty;

    final data = MediaQuery.of(context);
    final clampedScaler = TextScaler.linear(data.textScaler.scale(1).clamp(1.0, 1.15));

    return MediaQuery(
      data: data.copyWith(textScaler: clampedScaler),
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: provider.fetchBusinessInfo,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _HeaderCard(
                  onEdit: () => _openEditor(context, info),
                ),
                const SizedBox(height: 16),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 140),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  const _SectionTitle(
                    title: 'Store Details',
                    subtitle: 'Basic business identity for the owner app.',
                  ),
                  const SizedBox(height: 10),
                  _DetailTile(
                    icon: Icons.store_outlined,
                    color: const Color(0xFF0F3D91),
                    title: 'Store Name',
                    value: _displayValue(info['store_name']),
                  ),
                  _DetailTile(
                    icon: Icons.apartment_outlined,
                    color: const Color(0xFF0F3D91),
                    title: 'Branch Name',
                    value: _displayValue(info['branch_name']),
                  ),
                  _DetailTile(
                    icon: Icons.currency_exchange_outlined,
                    color: const Color(0xFF0F3D91),
                    title: 'Currency Code',
                    value: _displayValue(info['currency_code'], fallback: 'LKR'),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Contact',
                    subtitle: 'Business contact details.',
                  ),
                  const SizedBox(height: 10),
                  _DetailTile(
                    icon: Icons.phone_outlined,
                    color: const Color(0xFF147A5A),
                    title: 'Phone Number',
                    value: _displayValue(info['phone_number']),
                  ),
                  _DetailTile(
                    icon: Icons.alternate_email_outlined,
                    color: const Color(0xFF147A5A),
                    title: 'Email',
                    value: _displayValue(info['email']),
                  ),
                  _DetailTile(
                    icon: Icons.location_on_outlined,
                    color: const Color(0xFF147A5A),
                    title: 'Address',
                    value: _displayValue(info['address']),
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Operations',
                    subtitle: 'Useful business details for daily reference.',
                  ),
                  const SizedBox(height: 10),
                  _DetailTile(
                    icon: Icons.schedule_outlined,
                    color: const Color(0xFF9C5A00),
                    title: 'Business Hours',
                    value: _displayValue(info['business_hours']),
                  ),
                  _DetailTile(
                    icon: Icons.sticky_note_2_outlined,
                    color: const Color(0xFF7A1CAC),
                    title: 'Business Note',
                    value: _displayValue(info['business_note']),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.onEdit,
  });

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2A4D), Color(0xFF364B7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x2FFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C162544),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.store_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Business Info',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              height: 1.06,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: onEdit,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.16),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Store details, contact info, and business settings.',
                      style: TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
            color: Color(0xFF172433),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B14213D),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172433),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5E6B80),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF172433),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF344054),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: const Color(0xFFF8FAFD),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: const Color(0xFF6B7A90),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 44),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            hintStyle: const TextStyle(
              color: Color(0xFF98A2B3),
              fontWeight: FontWeight.w500,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0F3D91), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
