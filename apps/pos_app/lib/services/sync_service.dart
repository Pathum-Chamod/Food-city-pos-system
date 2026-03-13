import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'database_helper.dart';

class SyncService {
  Timer? _syncTimer;
  bool _isSyncing = false;

  // LOCAL (Windows desktop development)
  final String apiUrl = "http://127.0.0.1:8080/api/pos_sync.php";

  // LIVE (production)
  // final String apiUrl = "https://alfasoft.it.com/api/pos_sync.php";

  bool get _isLocalServer =>
      apiUrl.contains('127.0.0.1') || apiUrl.contains('localhost');

  void startSyncWorker() {
    // Poll the queue every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _attemptSync();
    });
    debugPrint("🔄 Background Sync Worker Started...");
  }

  Future<void> _attemptSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // For live/cloud mode, require internet connectivity.
      // For local Python backend mode, skip this check because loopback works
      // even without external internet.
      if (!_isLocalServer) {
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.contains(ConnectivityResult.none)) {
          debugPrint("📴 Offline. Sync skipped.");
          _isSyncing = false;
          return;
        }
      }

      // Fetch pending sync items from local SQLite
      final db = await DatabaseHelper.instance.database;
      final pendingItems = await db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
      );

      if (pendingItems.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint(
        "📤 Found ${pendingItems.length} pending items. Pushing sync queue...",
      );

      // Upload each pending item
      for (final item in pendingItems) {
        final success = await _uploadToBackend(item);

        if (success) {
          await db.update(
            'sync_queue',
            {'status': 'synced'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          debugPrint(
            "✅ Item ${item['id']} (${item['type']}) synced successfully.",
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Sync Engine Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // Upload one queued event to backend
  Future<bool> _uploadToBackend(Map<String, dynamic> item) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=pos_sync'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "type": item['type'],
          "data": item['data'],
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['status'] == 'success') {
          return true;
        } else {
          debugPrint("⚠️ Backend Error: ${result['message']}");
          return false;
        }
      }

      debugPrint("⚠️ Unexpected HTTP status: ${response.statusCode}");
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