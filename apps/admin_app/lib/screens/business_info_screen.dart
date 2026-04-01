import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

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
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Store name is required.')),
                );
                return;
              }

              setSheetState(() => isSaving = true);
              final message = await this.context.read<AdminProvider>().updateBusinessInfo(
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
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Business info updated.')),
                );
              } else {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(message)),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
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
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF172433),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Update the business details shown in the owner app.',
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSaving ? null : () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _EditorField(
                          label: 'Store Name',
                          controller: storeNameController,
                          hintText: 'Food City',
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Branch Name',
                          controller: branchNameController,
                          hintText: 'Main Branch',
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Phone Number',
                          controller: phoneController,
                          hintText: '077 123 4567',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Email',
                          controller: emailController,
                          hintText: 'store@email.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Address',
                          controller: addressController,
                          hintText: 'Store address',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Business Hours',
                          controller: hoursController,
                          hintText: '8:00 AM - 10:00 PM',
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Currency Code',
                          controller: currencyController,
                          hintText: 'LKR',
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),
                        _EditorField(
                          label: 'Business Note',
                          controller: noteController,
                          hintText: 'Optional note',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isSaving ? null : submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F3D91),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
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
                            label: Text(isSaving ? 'Saving...' : 'Save Business Info'),
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                _TopBar(onBack: () => Navigator.maybePop(context)),
                const SizedBox(height: 14),
                _HeaderCard(onEdit: () => _openEditor(context, info)),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF172433)),
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Business Info',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172433),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Store details and business settings.',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF222B45), Color(0xFF3F4C6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.store_outlined, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Business Info',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Store details, contact info, and business settings.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.14),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
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
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF172433),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w500,
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.12),
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
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w500,
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

class _EditorField extends StatelessWidget {
  const _EditorField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
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
            fontWeight: FontWeight.w700,
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF0F3D91), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
