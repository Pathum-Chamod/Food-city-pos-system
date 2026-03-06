import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_helper.dart';

class SyncService {
  Timer? _syncTimer;
  bool _isSyncing = false;

  // Start the background worker when the app boots
  void startSyncWorker() {
    // Run the check every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _attemptSync();
    });
    debugPrint("🔄 Background Sync Worker Started...");
  }

  Future<void> _attemptSync() async {
    // 1. Prevent overlapping syncs
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // 2. Check if we have internet
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint("📴 Offline. Sync skipped.");
        _isSyncing = false;
        return;
      }

      // 3. Internet is available! Get pending items from SQLite
      final db = await DatabaseHelper.instance.database;
      final pendingItems = await db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
      );

      if (pendingItems.isEmpty) {
        // debugPrint("✅ Everything is synced.");
        _isSyncing = false;
        return;
      }

      debugPrint("📤 Found ${pendingItems.length} pending items. Attempting upload...");

      // 4. Loop through and upload (Mocking the API call for now)
      for (var item in pendingItems) {
        bool success = await _mockApiUpload(item['data'].toString());
        
        if (success) {
          // 5. Update local status to 'synced'
          await db.update(
            'sync_queue',
            {'status': 'synced'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          debugPrint("✅ Item ${item['id']} synced successfully!");
        }
      }
    } catch (e) {
      debugPrint("❌ Sync Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // We will replace this with your real Spaceship API later!
  Future<bool> _mockApiUpload(String payload) async {
    // Simulating network delay
    await Future.delayed(const Duration(seconds: 1));
    return true; // Pretending the server received it
  }

  void stopSyncWorker() {
    _syncTimer?.cancel();
  }
}
