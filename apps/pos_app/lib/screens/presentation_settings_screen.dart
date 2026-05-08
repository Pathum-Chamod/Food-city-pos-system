import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/presentation_mode_service.dart';
import '../widgets/app_snackbar.dart';

class PresentationSettingsScreen extends StatefulWidget {
  const PresentationSettingsScreen({super.key});

  @override
  State<PresentationSettingsScreen> createState() => _PresentationSettingsScreenState();
}

class _PresentationSettingsScreenState extends State<PresentationSettingsScreen> {
  final TextEditingController _intervalController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft => _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border => _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary => _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary => _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings = await PresentationModeService.instance.getSettings();
      if (!mounted) return;
      _intervalController.text = settings.transactionInterval.toString();
      _pinController.text = settings.presentationPin;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load presentation settings: $e', color: _danger);
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    final auth = context.read<AuthProvider>();
    if (!auth.hasFullAccess) {
      _showMessage('Only owner/full-access login can change presentation settings.', color: _warning);
      return;
    }

    final interval = int.tryParse(_intervalController.text.trim());
    final pin = _pinController.text.trim();

    if (interval == null) {
      _showMessage('Enter a valid whole number for the interval.', color: _warning);
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage('Presentation PIN must be exactly 4 digits.', color: _warning);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await PresentationModeService.instance.saveSettings(
        transactionInterval: interval,
        presentationPin: pin,
        actorUserId: auth.currentUser?.id,
        actorName: auth.currentUser?.name ?? 'System',
      );

      if (!mounted) return;
      _showMessage('Presentation settings saved successfully.', color: _success);
      await _loadSettings();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''), color: _danger);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message, {required Color color}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: _panelSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleTable() {
    final interval = int.tryParse(_intervalController.text.trim()) ?? 3;
    final normalized = PresentationModeService.instance.normalizeInterval(interval);
    final realIds = List<int>.generate(10, (index) => index + 1);
    final visible = <int>[];
    for (var i = 0; i < realIds.length; i++) {
      if (normalized <= 1 || i % normalized == 0) {
        visible.add(realIds[i]);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Real transactions: ${realIds.join(', ')}',
            style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Special login uses real IDs: ${visible.join(', ')}',
            style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Special login displays as: ${List<int>.generate(visible.length, (index) => index + 1).join(', ')}',
            style: const TextStyle(color: _brand, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.hasFullAccess) {
      return Scaffold(
        backgroundColor: _page,
        appBar: AppBar(title: const Text('Presentation Settings')),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: _border),
            ),
            child: const Text(
              'Only owner/full-access login can change presentation settings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Presentation Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isSaving ? null : _loadSettings,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(_isDark ? 0.24 : 0.05),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: _brand.withOpacity(_isDark ? 0.16 : 0.10),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(Icons.visibility_rounded, color: _brand),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Special Presentation Login',
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Control how many real transactions are visible when using the special demo login.',
                                        style: TextStyle(
                                          color: _textSecondary,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            _buildInfoCard(
                              icon: Icons.info_outline_rounded,
                              title: 'Real sales are not changed',
                              description:
                                  'Sales made in presentation login are saved normally, reduce stock normally, and appear fully when you login as owner/manager. Only the presentation view is filtered.',
                              color: _blue,
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _intervalController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (_) => setState(() {}),
                              decoration: _inputDecoration(
                                label: 'Transaction visibility interval',
                                hint: 'Example: 3',
                                icon: Icons.filter_alt_rounded,
                                helperText:
                                    '1 = show all. 3 = show 1, 4, 7, 10. 4 = show 1, 5, 9.',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: true,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: _inputDecoration(
                                label: 'Presentation login PIN',
                                hint: '4-digit PIN',
                                icon: Icons.pin_rounded,
                                helperText:
                                    'This creates/updates the special Presentation Login user.',
                              ).copyWith(counterText: ''),
                            ),
                            const SizedBox(height: 16),
                            _buildExampleTable(),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    label: const Text('Back'),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSaving ? null : _saveSettings,
                                    icon: _isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.save_rounded),
                                    label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
