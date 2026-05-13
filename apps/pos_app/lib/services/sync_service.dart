import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/models/product.dart';

import 'database_helper.dart';

class SyncService {
  SyncService._internal();

  static final SyncService _instance = SyncService._internal();

  factory SyncService() => _instance;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // LOCAL (Windows desktop development)
  final String apiUrl = "http://127.0.0.1:8080/api/pos_sync.php";

  // LIVE (production)
  // final String apiUrl = "https://alfasoft.it.com/api/pos_sync.php";

  bool get _isLocalServer =>
      apiUrl.contains('127.0.0.1') || apiUrl.contains('localhost');

  void startSyncWorker() {
    if (_syncTimer?.isActive ?? false) return;

    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      syncNow();
    });

    syncNow();
    debugPrint("🔄 Background Sync Worker Started...");
  }

  Future<int> syncNow() async {
    if (_isSyncing) return 0;
    _isSyncing = true;

    int syncedCount = 0;

    try {
      if (!_isLocalServer) {
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.contains(ConnectivityResult.none)) {
          debugPrint("📴 Offline. Sync skipped.");
          return 0;
        }
      }

      final db = await DatabaseHelper.instance.database;

      final pendingItems = await db.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'id ASC',
      );

      if (pendingItems.isEmpty) {
        return 0;
      }

      debugPrint(
        "📤 Found ${pendingItems.length} pending items. Pushing sync queue...",
      );

      for (final item in pendingItems) {
        final success = await _uploadToBackend(item);

        if (success) {
          await db.update(
            'sync_queue',
            {'status': 'synced'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );

          syncedCount++;
          debugPrint(
            "✅ Item ${item['id']} (${item['type']}) synced successfully.",
          );
        }
      }

      return syncedCount;
    } catch (e) {
      debugPrint("❌ Sync Engine Error: $e");
      return syncedCount;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> refreshProductsFromBackend() async {
    try {
      if (!_isLocalServer) {
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult.contains(ConnectivityResult.none)) {
          debugPrint("📴 Offline. Product refresh skipped.");
          return false;
        }
      }

      final response = await http.get(
        Uri.parse('$apiUrl?action=get_products'),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode != 200) {
        debugPrint("⚠️ Product refresh failed: HTTP ${response.statusCode}");
        return false;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        debugPrint("⚠️ Product refresh failed: invalid response format");
        return false;
      }

      final products = decoded
          .map((item) => Product.fromMap(Map<String, dynamic>.from(item)))
          .toList();

      await DatabaseHelper.instance.replaceProductsFromBackend(products);

      debugPrint(
        "🔄 Product catalog refreshed from backend (${products.length} items).",
      );
      return true;
    } catch (e) {
      debugPrint("❌ Product refresh error: $e");
      return false;
    }
  }

  Future<bool> _uploadToBackend(Map<String, dynamic> item) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=pos_sync'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"type": item['type'], "data": item['data']}),
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

      debugPrint(
        "⚠️ Unexpected HTTP status: ${response.statusCode} "
        "for item ${item['id']} (${item['type']}): ${response.body}",
      );
      return false;
    } catch (e) {
      debugPrint("🌐 Network Upload Error: $e");
      return false;
    }
  }

  void stopSyncWorker() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}
