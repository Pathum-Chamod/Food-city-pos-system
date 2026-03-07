import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class SyncService {
  Timer? _syncTimer;
  bool _isSyncing = false;

  // ⚠️ YOUR LIVE SPACESHIP API URL
  final String apiUrl = "https://alfasoft.it.com/api/pos_sync.php";

  void startSyncWorker() {
    // Poll the queue every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _attemptSync();
    });
    debugPrint("🔄 Live Background Sync Worker Started...");
  }

  Future<void> _attemptSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // 1. Check Internet Connection
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint("📴 Offline. Sync skipped.");
        _isSyncing = false;
        return;
      }

      // 2. Fetch pending items from local SQLite
      final db = await DatabaseHelper.instance.database;
      final pendingItems = await db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
      );

      if (pendingItems.isEmpty) {
        _isSyncing = false;
        return; // Nothing to sync
      }

      debugPrint("📤 Found ${pendingItems.length} pending items. Pushing to Alfasoft Cloud...");

      // 3. Process the queue
      for (var item in pendingItems) {
        // We pass the entire item (which contains 'type' and 'data') to the upload function
        bool success = await _uploadToCloud(item);
        
        if (success) {
          // 4. Mark as synced locally so it doesn't upload again
          await db.update(
            'sync_queue',
            {'status': 'synced'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          debugPrint("✅ Item ${item['id']} (${item['type']}) synced successfully to Spaceship!");
        }
      }
    } catch (e) {
      debugPrint("❌ Sync Engine Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // The real HTTP POST request to your PHP middleman
  Future<bool> _uploadToCloud(Map<String, dynamic> item) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=sync_queue'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": item['type'],
          "data": item['data'] // The JSON string payload we created during checkout
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['status'] == 'success') {
          return true;
        } else {
          debugPrint("⚠️ Cloud DB Error: ${result['message']}");
          return false;
        }
      }
      return false;
    } catch (e) {
      debugPrint("🌐 Network Upload Error: $e");
      return false;
    }
  }

  void stopSyncWorker() {
    _syncTimer?.cancel();
  }
}
