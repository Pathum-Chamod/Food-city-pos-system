import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';

class BackupMetadata {
  const BackupMetadata({
    required this.app,
    required this.backupVersion,
    required this.createdAt,
    required this.deviceName,
    required this.createdBy,
    required this.containsPosDb,
    required this.containsServerDb,
    required this.posDbName,
    required this.serverDbName,
    required this.counts,
    required this.notes,
  });

  final String app;
  final int backupVersion;
  final String createdAt;
  final String deviceName;
  final String createdBy;
  final bool containsPosDb;
  final bool containsServerDb;
  final String posDbName;
  final String serverDbName;
  final Map<String, int> counts;
  final String notes;

  Map<String, dynamic> toJson() {
    return {
      'app': app,
      'backup_version': backupVersion,
      'created_at': createdAt,
      'device_name': deviceName,
      'created_by': createdBy,
      'contains': {'pos_db': containsPosDb, 'server_db': containsServerDb},
      'database_files': {
        'pos_db_name': posDbName,
        'server_db_name': serverDbName,
      },
      'counts': counts,
      'notes': notes,
    };
  }

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final contains = _readMap(json['contains']);
    final databaseFiles = _readMap(json['database_files']);
    final rawCounts = _readMap(json['counts']);
    final counts = <String, int>{};
    for (final entry in rawCounts.entries) {
      counts[entry.key] = _readInt(entry.value);
    }

    return BackupMetadata(
      app: (json['app'] ?? '').toString(),
      backupVersion: _readInt(json['backup_version']),
      createdAt: (json['created_at'] ?? '').toString(),
      deviceName: (json['device_name'] ?? '').toString(),
      createdBy: (json['created_by'] ?? '').toString(),
      containsPosDb: _readBool(contains['pos_db']),
      containsServerDb: _readBool(contains['server_db']),
      posDbName: (databaseFiles['pos_db_name'] ?? 'food_city_pos.db')
          .toString(),
      serverDbName: (databaseFiles['server_db_name'] ?? 'local_admin.db')
          .toString(),
      counts: counts,
      notes: (json['notes'] ?? '').toString(),
    );
  }

  static Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes';
  }

  static int _readInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class BackupFileInfo {
  const BackupFileInfo({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAt,
    this.metadata,
    this.validation,
  });

  final File file;
  final String fileName;
  final int sizeBytes;
  final DateTime modifiedAt;
  final BackupMetadata? metadata;
  final BackupValidationResult? validation;

  bool get isValid => validation?.isValid ?? false;
  bool get isAutoBackup =>
      fileName.startsWith(BackupRestoreService.autoBackupPrefix);
  bool get isManualBackup => !isAutoBackup;
}

class BackupResult {
  const BackupResult({
    required this.isSuccess,
    required this.message,
    this.file,
    this.metadata,
  });

  final bool isSuccess;
  final String message;
  final File? file;
  final BackupMetadata? metadata;
}

class RestoreResult {
  const RestoreResult({
    required this.isSuccess,
    required this.message,
    this.safetyBackupFile,
    this.metadata,
  });

  final bool isSuccess;
  final String message;
  final File? safetyBackupFile;
  final BackupMetadata? metadata;
}

class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    required this.message,
    this.metadata,
    this.containsPosDb = false,
    this.containsServerDb = false,
  });

  final bool isValid;
  final String message;
  final BackupMetadata? metadata;
  final bool containsPosDb;
  final bool containsServerDb;
}

class AutoBackupSettings {
  const AutoBackupSettings({
    required this.isEnabled,
    required this.intervalHours,
    required this.retentionCount,
    this.lastBackupAt,
  });

  final bool isEnabled;
  final int intervalHours;
  final int retentionCount;
  final DateTime? lastBackupAt;

  bool get isDue {
    if (!isEnabled) return false;
    final last = lastBackupAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inHours >= intervalHours;
  }

  AutoBackupSettings copyWith({
    bool? isEnabled,
    int? intervalHours,
    int? retentionCount,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
  }) {
    return AutoBackupSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      intervalHours: intervalHours ?? this.intervalHours,
      retentionCount: retentionCount ?? this.retentionCount,
      lastBackupAt: clearLastBackupAt
          ? null
          : lastBackupAt ?? this.lastBackupAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_enabled': isEnabled,
      'interval_hours': intervalHours,
      'retention_count': retentionCount,
      'last_backup_at': lastBackupAt?.toIso8601String(),
    };
  }

  factory AutoBackupSettings.fromJson(Map<String, dynamic> json) {
    final interval = BackupMetadata._readInt(json['interval_hours']);
    final retention = BackupMetadata._readInt(json['retention_count']);
    const allowedIntervals = {6, 12, 24, 72, 168};
    const allowedRetentionCounts = {1, 2, 3, 4, 5};
    return AutoBackupSettings(
      isEnabled: BackupMetadata._readBool(json['is_enabled']),
      intervalHours: allowedIntervals.contains(interval) ? interval : 24,
      retentionCount: allowedRetentionCounts.contains(retention)
          ? retention
          : 5,
      lastBackupAt: DateTime.tryParse(
        (json['last_backup_at'] ?? '').toString(),
      ),
    );
  }

  static const defaults = AutoBackupSettings(
    isEnabled: true,
    intervalHours: 24,
    retentionCount: 5,
  );
}

class BackupRestoreService {
  BackupRestoreService._();

  static final BackupRestoreService instance = BackupRestoreService._();

  static const int supportedBackupVersion = 1;
  static const String posDbFileName = 'food_city_pos.db';
  static const String metadataFileName = 'backup_metadata.json';
  static const String instructionsFileName = 'restore_instructions.txt';
  static const String settingsFileName = 'backup_settings.json';
  static const String manualBackupPrefix = 'food_city_backup';
  static const String autoBackupPrefix = 'food_city_auto_backup';

  Future<Directory> defaultBackupDirectory() async {
    final env = Platform.environment;
    final userProfile = (env['USERPROFILE'] ?? '').trim();
    final documentsPath = userProfile.isEmpty
        ? p.join(Directory.current.path, 'FoodCityPOS', 'Backups')
        : p.join(userProfile, 'Documents', 'FoodCityPOS', 'Backups');
    final directory = Directory(documentsPath);
    await directory.create(recursive: true);
    return directory;
  }

  Future<BackupResult> createBackup({
    bool includeServerDb = false,
    String createdBy = 'System',
    String notes = 'Manual backup created from POS app',
    String fileNamePrefix = manualBackupPrefix,
  }) async {
    try {
      final backupDirectory = await defaultBackupDirectory();
      final dbPath = await DatabaseHelper.instance.databasePath;
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return BackupResult(
          isSuccess: false,
          message: 'POS database file was not found at $dbPath.',
        );
      }

      await DatabaseHelper.instance.checkpointDatabaseForBackup();
      final dbBytes = await dbFile.readAsBytes();
      if (dbBytes.isEmpty) {
        return const BackupResult(
          isSuccess: false,
          message: 'POS database file is empty. Backup was not created.',
        );
      }

      final now = DateTime.now();
      final metadata = BackupMetadata(
        app: 'Food City POS',
        backupVersion: supportedBackupVersion,
        createdAt: now.toIso8601String(),
        deviceName: _deviceName(),
        createdBy: _clean(createdBy, fallback: 'System'),
        containsPosDb: true,
        containsServerDb: false,
        posDbName: posDbFileName,
        serverDbName: 'local_admin.db',
        counts: await _collectCounts(),
        notes: notes,
      );

      final archive = Archive();
      archive.addFile(ArchiveFile(posDbFileName, dbBytes.length, dbBytes));
      final metadataBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      );
      archive.addFile(
        ArchiveFile(metadataFileName, metadataBytes.length, metadataBytes),
      );
      final instructionsBytes = utf8.encode(_restoreInstructions());
      archive.addFile(
        ArchiveFile(
          instructionsFileName,
          instructionsBytes.length,
          instructionsBytes,
        ),
      );

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes.isEmpty) {
        return const BackupResult(
          isSuccess: false,
          message: 'Could not create backup ZIP.',
        );
      }

      final backupFile = File(
        p.join(backupDirectory.path, '${fileNamePrefix}_${_stamp(now)}.zip'),
      );
      await backupFile.writeAsBytes(zipBytes, flush: true);

      return BackupResult(
        isSuccess: true,
        message: 'Backup created successfully.',
        file: backupFile,
        metadata: metadata,
      );
    } catch (e) {
      return BackupResult(isSuccess: false, message: 'Backup failed: $e');
    }
  }

  Future<AutoBackupSettings> loadAutoBackupSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      await saveAutoBackupSettings(AutoBackupSettings.defaults);
      return AutoBackupSettings.defaults;
    }

    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        return AutoBackupSettings.fromJson(json);
      }
      if (json is Map) {
        return AutoBackupSettings.fromJson(
          json.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (e) {
      debugPrint('Could not read auto backup settings: $e');
    }
    return AutoBackupSettings.defaults;
  }

  Future<void> saveAutoBackupSettings(AutoBackupSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
  }

  Future<BackupResult?> runAutoBackupIfDue({
    String createdBy = 'System',
  }) async {
    final settings = await loadAutoBackupSettings();
    if (!settings.isDue) return null;

    final result = await createBackup(
      createdBy: createdBy,
      notes: 'Automatic scheduled backup',
      fileNamePrefix: autoBackupPrefix,
    );
    if (result.isSuccess) {
      await saveAutoBackupSettings(
        settings.copyWith(lastBackupAt: DateTime.now()),
      );
      await pruneAutoBackups(retentionCount: settings.retentionCount);
    }
    return result;
  }

  Future<void> pruneAutoBackups({required int retentionCount}) async {
    if (retentionCount <= 0) return;
    final directory = await defaultBackupDirectory();
    final autoBackups = await directory
        .list()
        .where(
          (entity) =>
              entity is File &&
              p.basename(entity.path).startsWith(autoBackupPrefix) &&
              entity.path.endsWith('.zip'),
        )
        .cast<File>()
        .toList();

    final filesWithStats = <({File file, DateTime modified})>[];
    for (final file in autoBackups) {
      final stat = await file.stat();
      filesWithStats.add((file: file, modified: stat.modified));
    }
    filesWithStats.sort((a, b) => b.modified.compareTo(a.modified));

    for (final item in filesWithStats.skip(retentionCount)) {
      await _deleteFileIfExists(item.file.path);
    }
  }

  Future<BackupResult> deleteManualBackup(File backupFile) async {
    try {
      final directory = await defaultBackupDirectory();
      final backupDirPath = p.normalize(p.absolute(directory.path));
      final filePath = p.normalize(p.absolute(backupFile.path));

      if (!p.isWithin(backupDirPath, filePath) && filePath != backupDirPath) {
        return const BackupResult(
          isSuccess: false,
          message: 'Only backups in the POS backup folder can be deleted.',
        );
      }

      final fileName = p.basename(filePath);
      if (!fileName.endsWith('.zip') || fileName.startsWith(autoBackupPrefix)) {
        return const BackupResult(
          isSuccess: false,
          message: 'Only manual backup files can be deleted here.',
        );
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return const BackupResult(
          isSuccess: false,
          message: 'Backup file was already removed.',
        );
      }

      await file.delete();
      return const BackupResult(
        isSuccess: true,
        message: 'Manual backup deleted.',
      );
    } catch (e) {
      return BackupResult(
        isSuccess: false,
        message: 'Could not delete backup: $e',
      );
    }
  }

  Future<List<BackupFileInfo>> listBackups() async {
    final directory = await defaultBackupDirectory();
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .cast<File>()
        .toList();

    final infos = <BackupFileInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      final validation = await validateBackup(file);
      infos.add(
        BackupFileInfo(
          file: file,
          fileName: p.basename(file.path),
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
          metadata: validation.metadata,
          validation: validation,
        ),
      );
    }

    infos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return infos;
  }

  Future<BackupValidationResult> validateBackup(File backupFile) async {
    try {
      if (!await backupFile.exists()) {
        return const BackupValidationResult(
          isValid: false,
          message: 'Backup file does not exist.',
        );
      }

      final bytes = await backupFile.readAsBytes();
      if (bytes.isEmpty) {
        return const BackupValidationResult(
          isValid: false,
          message: 'Backup file is empty.',
        );
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      final metadataEntry = archive.findFile(metadataFileName);
      if (metadataEntry == null) {
        return const BackupValidationResult(
          isValid: false,
          message: 'backup_metadata.json is missing.',
        );
      }

      final metadataText = utf8.decode(_entryBytes(metadataEntry));
      final metadata = BackupMetadata.fromJson(
        jsonDecode(metadataText) as Map<String, dynamic>,
      );
      if (metadata.app != 'Food City POS') {
        return BackupValidationResult(
          isValid: false,
          message: 'This is not a Food City POS backup.',
          metadata: metadata,
        );
      }
      if (metadata.backupVersion != supportedBackupVersion) {
        return BackupValidationResult(
          isValid: false,
          message: 'Unsupported backup version ${metadata.backupVersion}.',
          metadata: metadata,
        );
      }

      final posDbEntry = archive.findFile(metadata.posDbName);
      if (posDbEntry == null) {
        return BackupValidationResult(
          isValid: false,
          message: '${metadata.posDbName} is missing.',
          metadata: metadata,
        );
      }
      if (posDbEntry.size <= 0) {
        return BackupValidationResult(
          isValid: false,
          message: '${metadata.posDbName} is empty.',
          metadata: metadata,
        );
      }

      return BackupValidationResult(
        isValid: true,
        message: 'Backup is valid.',
        metadata: metadata,
        containsPosDb: true,
        containsServerDb: archive.findFile(metadata.serverDbName) != null,
      );
    } catch (e) {
      return BackupValidationResult(
        isValid: false,
        message: 'Backup validation failed: $e',
      );
    }
  }

  Future<RestoreResult> restoreBackup(
    File backupFile, {
    String restoredBy = 'System',
  }) async {
    try {
      final validation = await validateBackup(backupFile);
      if (!validation.isValid || validation.metadata == null) {
        return RestoreResult(
          isSuccess: false,
          message: validation.message,
          metadata: validation.metadata,
        );
      }

      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final posDbEntry = archive.findFile(validation.metadata!.posDbName);
      if (posDbEntry == null) {
        return const RestoreResult(
          isSuccess: false,
          message: 'Backup does not contain a POS database file.',
        );
      }

      final dbBytes = _entryBytes(posDbEntry);
      if (dbBytes.isEmpty) {
        return const RestoreResult(
          isSuccess: false,
          message: 'Backup POS database is empty.',
        );
      }

      final tempDb = await _writeTempRestoreDb(dbBytes);
      final tempValidation = await _validateSqliteDatabase(tempDb);
      await _deleteFileIfExists(tempDb.path);
      if (!tempValidation.isValid) {
        return RestoreResult(
          isSuccess: false,
          message: tempValidation.message,
          metadata: validation.metadata,
        );
      }

      final safetyBackup = await createBackup(
        createdBy: restoredBy,
        notes: 'Automatic safety backup created before restore',
      );
      if (!safetyBackup.isSuccess || safetyBackup.file == null) {
        return RestoreResult(
          isSuccess: false,
          message:
              'Restore cancelled because the pre-restore safety backup failed: ${safetyBackup.message}',
          metadata: validation.metadata,
        );
      }

      final dbPath = await DatabaseHelper.instance.databasePath;
      await DatabaseHelper.instance.closeDatabaseForRestore();
      await _deleteFileIfExists('$dbPath-wal');
      await _deleteFileIfExists('$dbPath-shm');

      final dbFile = File(dbPath);
      await dbFile.parent.create(recursive: true);
      await dbFile.writeAsBytes(dbBytes, flush: true);

      return RestoreResult(
        isSuccess: true,
        message:
            'Backup restored successfully. Restart the POS app before continuing sales.',
        safetyBackupFile: safetyBackup.file,
        metadata: validation.metadata,
      );
    } catch (e) {
      return RestoreResult(isSuccess: false, message: 'Restore failed: $e');
    }
  }

  Future<Map<String, int>> _collectCounts() async {
    final db = await DatabaseHelper.instance.database;
    final counts = <String, int>{};
    final tables = <String, String>{
      'products': 'products',
      'customers': 'customers',
      'sales': 'sales',
      'customer_ledger_entries': 'customer_ledger',
      'loyalty_ledger_entries': 'loyalty_ledger',
      'pricing_schemes': 'pricing_schemes',
      'customer_product_prices': 'customer_product_prices',
    };

    for (final entry in tables.entries) {
      counts[entry.key] = await _safeCount(db, entry.value);
    }
    return counts;
  }

  Future<File> _settingsFile() async {
    final directory = await defaultBackupDirectory();
    return File(p.join(directory.path, settingsFileName));
  }

  Future<int> _safeCount(Database db, String table) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      final value = rows.isEmpty ? null : rows.first['count'];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    } catch (e) {
      debugPrint('Backup count skipped for $table: $e');
      return 0;
    }
  }

  Future<File> _writeTempRestoreDb(List<int> bytes) async {
    final tempDir = await Directory.systemTemp.createTemp('food_city_restore_');
    final tempDb = File(p.join(tempDir.path, posDbFileName));
    await tempDb.writeAsBytes(bytes, flush: true);
    return tempDb;
  }

  Future<BackupValidationResult> _validateSqliteDatabase(File dbFile) async {
    Database? db;
    try {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        dbFile.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables
          .map((row) => (row['name'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toSet();
      final requiredTables = {'products', 'customers', 'sales'};
      final missing = requiredTables
          .where((table) => !tableNames.contains(table))
          .toList();
      if (missing.isNotEmpty) {
        return BackupValidationResult(
          isValid: false,
          message: 'Backup database is missing tables: ${missing.join(', ')}.',
        );
      }
      return const BackupValidationResult(
        isValid: true,
        message: 'Backup database can be opened.',
      );
    } catch (e) {
      return BackupValidationResult(
        isValid: false,
        message: 'Backup database could not be opened: $e',
      );
    } finally {
      await db?.close();
    }
  }

  Future<void> _deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  List<int> _entryBytes(ArchiveFile file) {
    return file.content as List<int>;
  }

  String _deviceName() {
    final env = Platform.environment;
    final name = (env['COMPUTERNAME'] ?? env['HOSTNAME'] ?? '').trim();
    return name.isEmpty ? 'Unknown Device' : name;
  }

  String _clean(String value, {required String fallback}) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  String _stamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}-'
        '${value.minute.toString().padLeft(2, '0')}-'
        '${value.second.toString().padLeft(2, '0')}';
  }

  String _restoreInstructions() {
    return 'Food City POS Backup\n\n'
        'This ZIP contains a local POS database backup and metadata.\n'
        'Restore must be done from the POS Backup & Restore screen.\n'
        'Do not manually replace database files while the POS app is open.\n';
  }
}
