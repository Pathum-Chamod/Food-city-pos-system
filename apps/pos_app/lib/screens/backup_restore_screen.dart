import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/backup_restore_service.dart';
import '../services/database_helper.dart';
import '../services/permission_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_guard.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  List<BackupFileInfo> _backups = [];
  Directory? _backupDirectory;
  AutoBackupSettings _autoSettings = AutoBackupSettings.defaults;
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isRestoring = false;
  bool _isSavingAutoSettings = false;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = BackupRestoreService.instance;
      final directory = await service.defaultBackupDirectory();
      final settings = await service.loadAutoBackupSettings();
      final backups = await service.listBackups();
      if (!mounted) return;
      setState(() {
        _backupDirectory = directory;
        _autoSettings = settings;
        _backups = backups;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load backups: $e', color: _danger);
    }
  }

  String get _currentUserName {
    final userName = context.read<AuthProvider>().currentUser?.name.trim();
    return userName?.isNotEmpty == true ? userName! : 'Manager';
  }

  Future<void> _logBackupAction({
    required String actionType,
    required String description,
  }) async {
    final auth = context.read<AuthProvider>();
    await DatabaseHelper.instance.logSensitiveAction(
      actorUserId: auth.currentUser?.id,
      actorName: auth.currentUser?.name,
      actionType: actionType,
      description: description,
    );
  }

  Future<void> _createBackup() async {
    if (_isCreating) return;
    setState(() {
      _isCreating = true;
    });

    final result = await BackupRestoreService.instance.createBackup(
      createdBy: _currentUserName,
    );

    if (!mounted) return;
    setState(() {
      _isCreating = false;
    });

    _showMessage(result.message, color: result.isSuccess ? _brand : _danger);

    if (result.isSuccess) {
      await _logBackupAction(
        actionType: 'backup_create',
        description:
            'Manual backup created: ${result.file?.path.split(Platform.pathSeparator).last ?? 'backup'}',
      );
      await _loadBackups();
    }
  }

  Future<void> _saveAutoSettings(AutoBackupSettings settings) async {
    setState(() {
      _autoSettings = settings;
      _isSavingAutoSettings = true;
    });

    try {
      await BackupRestoreService.instance.saveAutoBackupSettings(settings);
      if (!mounted) return;
      setState(() {
        _isSavingAutoSettings = false;
      });
      await _logBackupAction(
        actionType: 'backup_settings_update',
        description: 'Automatic backup settings updated',
      );
      _showMessage('Automatic backup settings saved.', color: _brand);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSavingAutoSettings = false;
      });
      _showMessage(
        'Could not save automatic backup settings: $e',
        color: _danger,
      );
    }
  }

  Future<void> _pickBackupToRestore() async {
    if (_isRestoring) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select Food City POS backup',
      initialDirectory: _backupDirectory?.path,
    );
    final path = picked?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    await _confirmAndRestore(File(path));
  }

  Future<void> _confirmAndRestore(File file) async {
    final validation = await BackupRestoreService.instance.validateBackup(file);
    if (!mounted) return;
    if (!validation.isValid) {
      _showMessage(validation.message, color: _danger);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final metadata = validation.metadata;
        return AlertDialog(
          title: const Text('Restore Backup?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will replace the current POS database with this backup. A safety backup of the current database will be created first.',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _detailRow(
                  'File',
                  file.path.split(Platform.pathSeparator).last,
                ),
                if (metadata != null) ...[
                  _detailRow('Created', _formatDateText(metadata.createdAt)),
                  _detailRow('Created By', metadata.createdBy),
                  _detailRow('Products', '${metadata.counts['products'] ?? 0}'),
                  _detailRow(
                    'Customers',
                    '${metadata.counts['customers'] ?? 0}',
                  ),
                  _detailRow('Sales', '${metadata.counts['sales'] ?? 0}'),
                ],
                const SizedBox(height: 14),
                Text(
                  'Restart the POS app after restore before making new sales.',
                  style: TextStyle(
                    color: _warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Restore Backup'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _restoreBackup(file);
  }

  Future<void> _restoreBackup(File file) async {
    if (_isRestoring) return;
    setState(() {
      _isRestoring = true;
    });

    final result = await BackupRestoreService.instance.restoreBackup(
      file,
      restoredBy: _currentUserName,
    );

    if (!mounted) return;
    setState(() {
      _isRestoring = false;
    });

    _showMessage(result.message, color: result.isSuccess ? _brand : _danger);

    if (result.isSuccess) {
      await _logBackupAction(
        actionType: 'backup_restore',
        description:
            'Backup restored from ${file.path.split(Platform.pathSeparator).last}',
      );
    }

    await _loadBackups();
  }

  Future<void> _openBackupFolder() async {
    final directory =
        _backupDirectory ??
        await BackupRestoreService.instance.defaultBackupDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [directory.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [directory.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [directory.path]);
      } else {
        _showMessage(directory.path, color: _blue);
      }
    } catch (_) {
      _showMessage(directory.path, color: _blue);
    }
  }

  Future<void> _confirmDeleteManualBackup(BackupFileInfo info) async {
    if (!info.isManualBackup) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Manual Backup?'),
        content: SizedBox(
          width: 440,
          child: Text(
            'This will permanently delete ${info.fileName}. Automatic backup retention will not be affected.',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final result = await BackupRestoreService.instance.deleteManualBackup(
      info.file,
    );
    if (!mounted) return;
    _showMessage(result.message, color: result.isSuccess ? _brand : _danger);
    if (result.isSuccess) {
      await _logBackupAction(
        actionType: 'backup_delete',
        description: 'Manual backup deleted: ${info.fileName}',
      );
      await _loadBackups();
    }
  }

  void _showDetails(BackupFileInfo info) {
    final metadata = info.metadata;
    final validation = info.validation;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Backup Details'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('File', info.fileName),
                  _detailRow('Size', _formatBytes(info.sizeBytes)),
                  _detailRow('Modified', _formatDate(info.modifiedAt)),
                  _detailRow(
                    'Validation',
                    validation?.message ?? 'Not validated',
                    valueColor: info.isValid ? _brand : _danger,
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 12),
                    _detailRow('Created', _formatDateText(metadata.createdAt)),
                    _detailRow('Device', metadata.deviceName),
                    _detailRow('Created By', metadata.createdBy),
                    _detailRow('POS DB', metadata.containsPosDb ? 'Yes' : 'No'),
                    _detailRow(
                      'Server DB',
                      metadata.containsServerDb ? 'Yes' : 'No',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Counts',
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...metadata.counts.entries.map(
                      (entry) => _detailRow(
                        _countLabel(entry.key),
                        entry.value.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message, {required Color color}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateText(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : _formatDate(parsed);
  }

  String _countLabel(String key) {
    return key
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? _textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusHeader() {
    final manualCount = _backups
        .where((backup) => backup.isManualBackup)
        .length;
    final autoCount = _backups.length - manualCount;
    final lastBackup = _backups.isEmpty ? null : _backups.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _metric(
            icon: Icons.folder_zip_rounded,
            label: 'Manual Backups',
            value: manualCount.toString(),
            color: _brand,
          ),
          const SizedBox(width: 12),
          _metric(
            icon: Icons.autorenew_rounded,
            label: 'Auto Backups',
            value: autoCount.toString(),
            color: _blue,
          ),
          const SizedBox(width: 12),
          _metric(
            icon: Icons.schedule_rounded,
            label: 'Last Backup',
            value: lastBackup == null
                ? 'None'
                : _formatDate(lastBackup.modifiedAt),
            color: lastBackup == null ? _warning : _textPrimary,
          ),
        ],
      ),
    );
  }

  Widget _autoBackupCard() {
    final settings = _autoSettings;
    final last = settings.lastBackupAt;
    final next = last == null
        ? 'Next app start'
        : _formatDate(last.add(Duration(hours: settings.intervalHours)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.autorenew_rounded, color: _brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic Backups',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  settings.isEnabled
                      ? 'Last: ${last == null ? 'Never' : _formatDate(last)}. Next due: $next.'
                      : 'Automatic backups are disabled.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int>(
              initialValue: settings.intervalHours,
              decoration: const InputDecoration(labelText: 'Every'),
              items: const [
                DropdownMenuItem(value: 6, child: Text('6 hours')),
                DropdownMenuItem(value: 12, child: Text('12 hours')),
                DropdownMenuItem(value: 24, child: Text('24 hours')),
                DropdownMenuItem(value: 72, child: Text('3 days')),
                DropdownMenuItem(value: 168, child: Text('7 days')),
              ],
              onChanged: _isSavingAutoSettings
                  ? null
                  : (value) {
                      if (value == null) return;
                      _saveAutoSettings(
                        settings.copyWith(intervalHours: value),
                      );
                    },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<int>(
              initialValue: settings.retentionCount,
              decoration: const InputDecoration(labelText: 'Keep Auto Backups'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 auto')),
                DropdownMenuItem(value: 2, child: Text('2 auto')),
                DropdownMenuItem(value: 3, child: Text('3 auto')),
                DropdownMenuItem(value: 4, child: Text('4 auto')),
                DropdownMenuItem(value: 5, child: Text('5 auto')),
              ],
              onChanged: _isSavingAutoSettings
                  ? null
                  : (value) {
                      if (value == null) return;
                      _saveAutoSettings(
                        settings.copyWith(retentionCount: value),
                      );
                    },
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: settings.isEnabled,
            onChanged: _isSavingAutoSettings
                ? null
                : (value) {
                    _saveAutoSettings(settings.copyWith(isEnabled: value));
                  },
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  Widget _backupCard(BackupFileInfo info) {
    final metadata = info.metadata;
    final valid = info.isValid;
    final statusColor = valid ? _brand : _danger;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: valid ? _border : _danger.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              valid ? Icons.verified_rounded : Icons.error_outline_rounded,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${metadata == null ? _formatDate(info.modifiedAt) : _formatDateText(metadata.createdAt)} • ${_formatBytes(info.sizeBytes)}',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  info.validation?.message ?? 'Not validated',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (metadata != null)
            SizedBox(
              width: 220,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('${metadata.counts['products'] ?? 0} products', _blue),
                  _chip(
                    '${metadata.counts['customers'] ?? 0} customers',
                    _brand,
                  ),
                  _chip('${metadata.counts['sales'] ?? 0} sales', _warning),
                ],
              ),
            ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _showDetails(info),
            icon: const Icon(Icons.info_outline_rounded, size: 16),
            label: const Text('Details'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: valid && !_isRestoring
                ? () => _confirmAndRestore(info.file)
                : null,
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Restore'),
          ),
          if (info.isManualBackup) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete manual backup',
              onPressed: () => _confirmDeleteManualBackup(info),
              icon: const Icon(Icons.delete_outline_rounded),
              color: _danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _backupSection({
    required String title,
    required String emptyMessage,
    required List<BackupFileInfo> backups,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        if (backups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Text(
              emptyMessage,
              style: TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...backups.expand(
            (backup) => [_backupCard(backup), const SizedBox(height: 10)],
          ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().can(PosPermission.backupRestore)) {
      return const PermissionGuard(
        permission: PosPermission.backupRestore,
        title: 'Backup access restricted',
        message:
            'Only managers or full-access users can use backup and restore.',
        child: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        actions: [
          TextButton.icon(
            onPressed: _isCreating || _isRestoring ? null : _openBackupFolder,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Open Folder'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _isCreating || _isRestoring
                ? null
                : _pickBackupToRestore,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Restore File'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading || _isRestoring ? null : _loadBackups,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating || _isRestoring ? null : _createBackup,
        icon: _isCreating || _isRestoring
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded),
        label: Text(
          _isRestoring
              ? 'Restoring...'
              : _isCreating
              ? 'Creating...'
              : 'Create Manual Backup',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              _statusHeader(),
              const SizedBox(height: 18),
              _autoBackupCard(),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _warning.withValues(alpha: _isDark ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _warning.withValues(alpha: 0.28)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: _warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Restore creates a safety backup first, then replaces the local POS database. Restart the POS app after a successful restore.',
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                        builder: (context) {
                          final manualBackups = _backups
                              .where((backup) => backup.isManualBackup)
                              .toList();
                          final autoBackups = _backups
                              .where((backup) => backup.isAutoBackup)
                              .toList();
                          return ListView(
                            children: [
                              _backupSection(
                                title: 'Manual Backups',
                                emptyMessage:
                                    'No manual backups yet. Use Create Manual Backup when you want a backup now.',
                                backups: manualBackups,
                              ),
                              const SizedBox(height: 10),
                              _backupSection(
                                title: 'Automatic Backups',
                                emptyMessage:
                                    'No automatic backups yet. They are created when the app starts and the schedule is due.',
                                backups: autoBackups,
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
