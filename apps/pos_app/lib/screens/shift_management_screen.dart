
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';

TextEditingController _selectedTextController(String text) {
  return TextEditingController.fromValue(
    TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    ),
  );
}

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
      _selectedTextController('0.00');
  final TextEditingController _closingCashController = TextEditingController();

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _pageAlt => _isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get _surface => _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _surfaceSoft => _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _surfaceAlt => _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _inputFill => _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _border => _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _borderStrong => _isDark ? const Color(0xFF31445E) : const Color(0xFFCED9E5);
  Color get _textPrimary => _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary => _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _textMuted => _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _brand => const Color(0xFF2AAA8A);
  Color get _brandSoft => _brand.withOpacity(_isDark ? 0.16 : 0.10);
  Color get _blue => const Color(0xFF4B8DFF);
  Color get _blueSoft => _blue.withOpacity(_isDark ? 0.18 : 0.10);
  Color get _success => const Color(0xFF1FCF9A);
  Color get _successSoft => _success.withOpacity(_isDark ? 0.18 : 0.12);
  Color get _warning => const Color(0xFFFFB65C);
  Color get _warningSoft => _warning.withOpacity(_isDark ? 0.20 : 0.14);
  Color get _danger => const Color(0xFFFF6B7A);
  Color get _dangerSoft => _danger.withOpacity(_isDark ? 0.20 : 0.12);
  Color get _purple => const Color(0xFF8B5CF6);
  Color get _purpleSoft => _purple.withOpacity(_isDark ? 0.18 : 0.12);
  Color get _shadowColor => Colors.black.withOpacity(_isDark ? 0.24 : 0.0);

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
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final summary = await DatabaseHelper.instance.getOpenShiftSummaryForCashier(
      widget.cashierName,
    );

    if (!mounted) return;

    setState(() {
      _openShiftSummary = summary;
      _isLoading = false;
    });
  }

  BoxDecoration _panelDecoration({Color? color, double radius = 24}) {
    return BoxDecoration(
      color: color ?? _surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: _shadowColor,
          blurRadius: 26,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  BoxDecoration _softDecoration({Color? color, double radius = 18}) {
    return BoxDecoration(
      color: color ?? _surfaceSoft,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required String labelText,
    IconData? icon,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixText: prefixText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _textMuted),
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        borderSide: BorderSide(color: _brand, width: 1.4),
      ),
      labelStyle: TextStyle(color: _textSecondary, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: _textSecondary.withOpacity(0.84), fontWeight: FontWeight.w500),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: isError ? _danger : _surfaceSoft,
    );
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

  String _money(dynamic value) {
    return 'Rs. ${(((value as num?) ?? 0).toDouble()).toStringAsFixed(2)}';
  }

  Widget _headerIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 44,
          height: 44,
          decoration: _softDecoration(color: _surfaceSoft, radius: 14),
          child: Icon(icon, color: iconColor ?? _textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(color: _surfaceSoft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showShiftClosedDialog({
    required double expectedCash,
    required double countedCash,
    required double variance,
  }) async {
    final tone = variance == 0
        ? _brand
        : (variance > 0 ? _success : _danger);
    final toneSoft = variance == 0
        ? _brandSoft
        : (variance > 0 ? _successSoft : _dangerSoft);

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Shift closed',
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  decoration: _panelDecoration(color: _surface),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: toneSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: tone.withOpacity(0.24)),
                            ),
                            child: Icon(
                              Icons.task_alt_rounded,
                              color: tone,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Shift Closed',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your shift has been closed successfully.',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _softDecoration(color: _surfaceSoft),
                        child: Column(
                          children: [
                            _summaryLine('Expected Cash', 'Rs. ${expectedCash.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            _summaryLine('Counted Cash', 'Rs. ${countedCash.toStringAsFixed(2)}'),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: toneSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: tone.withOpacity(0.24)),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Variance',
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Rs. ${variance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: tone,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _summaryLine(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Future<void> _openShift() async {
    if (_isSubmitting) return;

    final openingCash =
        double.tryParse(_openingCashController.text.trim()) ?? -1;

    if (openingCash < 0) {
      _showMessage('Enter a valid opening cash amount.', isError: true);
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

      _showMessage('Shift opened successfully.');
      await _loadShift();
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
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
      _showMessage('Enter a valid closing cash amount.', isError: true);
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

      await _showShiftClosedDialog(
        expectedCash: expectedCash,
        countedCash: closingCash,
        variance: variance,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildNoOpenShiftView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            decoration: _panelDecoration(color: _surface),
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_brandSoft, _blueSoft],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _border),
                      ),
                      child: Icon(Icons.point_of_sale_rounded, color: _brand, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open New Shift',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start a cashier shift with the opening cash amount.',
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
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _softDecoration(color: _surfaceSoft),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline_rounded, color: _textMuted, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        widget.cashierName,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _openingCashController,
                  textInputAction: TextInputAction.done,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) {
                    if (!_isSubmitting) _openShift();
                  },
                  decoration: _fieldDecoration(
                    hintText: '0.00',
                    labelText: 'Opening Cash',
                    icon: Icons.payments_outlined,
                    prefixText: 'Rs. ',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _openShift,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(_isSubmitting ? 'Opening...' : 'Open Shift'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
  }

  Widget _buildOpenShiftView(Map<String, dynamic> shift) {
    return RefreshIndicator(
      onRefresh: _loadShift,
      color: _brand,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        children: [
          Container(
            decoration: _panelDecoration(color: _surface),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;

                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_brandSoft, _blueSoft],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _border),
                              ),
                              child: Icon(Icons.badge_rounded, color: _brand, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Shift',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Live shift summary for ${widget.cashierName}',
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _infoPill(
                              icon: Icons.person_outline_rounded,
                              text: widget.cashierName,
                            ),
                            _infoPill(
                              icon: Icons.schedule_rounded,
                              text: _formatDateTime((shift['opened_at'] ?? '').toString()),
                            ),
                            _infoPill(
                              icon: Icons.payments_outlined,
                              text: 'Opening ${_money(shift['opening_cash'])}',
                            ),
                          ],
                        ),
                      ],
                    );

                    final refresh = _headerIconButton(
                      tooltip: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: _loadShift,
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: 14),
                          refresh,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: info),
                        const SizedBox(width: 12),
                        refresh,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final spacing = 12.0;
                    final columns = constraints.maxWidth >= 1080
                        ? 3
                        : constraints.maxWidth >= 680
                            ? 2
                            : 1;
                    final itemWidth = columns == 1
                        ? constraints.maxWidth
                        : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Cash Sales',
                            value: _money(shift['cash_sales_total']),
                            tone: _success,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Card Sales',
                            value: _money(shift['card_sales_total']),
                            tone: _blue,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Cash Refunds',
                            value: _money(shift['cash_refund_total']),
                            tone: _danger,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Expected Cash',
                            value: _money(shift['expected_cash']),
                            tone: _purple,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Transactions',
                            value: '${((shift['transaction_count'] as num?) ?? 0).toInt()}',
                            tone: _textPrimary,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildStatTile(
                            label: 'Refund Count',
                            value: '${((shift['refund_count'] as num?) ?? 0).toInt()}',
                            tone: _warning,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: _panelDecoration(color: _surface),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Close Shift',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter the counted cash in drawer to close this shift.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _closingCashController,
                  textInputAction: TextInputAction.done,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) {
                    if (!_isSubmitting) _closeShift();
                  },
                  decoration: _fieldDecoration(
                    hintText: '0.00',
                    labelText: 'Counted Cash at Close',
                    icon: Icons.calculate_outlined,
                    prefixText: 'Rs. ',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _closeShift,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_clock_outlined, size: 18),
                    label: Text(_isSubmitting ? 'Closing...' : 'Close Shift'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _softDecoration(color: _surfaceSoft, radius: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _textMuted, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shift = _openShiftSummary;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _page,
        foregroundColor: _textPrimary,
        title: const Text('Shift Management'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _brand))
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_page, _pageAlt],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: shift == null
                  ? _buildNoOpenShiftView()
                  : _buildOpenShiftView(shift),
            ),
    );
  }
}
