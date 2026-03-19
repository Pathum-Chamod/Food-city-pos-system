import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StockTakeDraft {
  const StockTakeDraft({
    required this.sessionName,
    required this.startedAtIso,
    required this.countedQuantities,
  });

  final String sessionName;
  final String startedAtIso;
  final Map<String, int> countedQuantities;

  Map<String, dynamic> toMap() {
    return {
      'session_name': sessionName,
      'started_at': startedAtIso,
      'counted_quantities': countedQuantities,
    };
  }

  factory StockTakeDraft.fromMap(Map<String, dynamic> map) {
    final rawCounts = map['counted_quantities'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return StockTakeDraft(
      sessionName: (map['session_name'] ?? 'Stock Take Session').toString(),
      startedAtIso: (map['started_at'] ?? DateTime.now().toIso8601String())
          .toString(),
      countedQuantities: rawCounts.map(
        (key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0),
      ),
    );
  }
}

class StockTakeHistoryLine {
  const StockTakeHistoryLine({
    required this.barcode,
    required this.productName,
    required this.systemStock,
    required this.countedStock,
    required this.applied,
  });

  final String barcode;
  final String productName;
  final int systemStock;
  final int countedStock;
  final bool applied;

  int get difference => countedStock - systemStock;

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'product_name': productName,
      'system_stock': systemStock,
      'counted_stock': countedStock,
      'applied': applied,
    };
  }

  factory StockTakeHistoryLine.fromMap(Map<String, dynamic> map) {
    return StockTakeHistoryLine(
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      systemStock: int.tryParse(map['system_stock'].toString()) ?? 0,
      countedStock: int.tryParse(map['counted_stock'].toString()) ?? 0,
      applied: map['applied'] == true,
    );
  }
}

class StockTakeHistoryEntry {
  const StockTakeHistoryEntry({
    required this.id,
    required this.sessionName,
    required this.startedAtIso,
    required this.appliedAtIso,
    required this.totalProducts,
    required this.countedItems,
    required this.discrepancyItems,
    required this.appliedItems,
    required this.lines,
  });

  final String id;
  final String sessionName;
  final String startedAtIso;
  final String appliedAtIso;
  final int totalProducts;
  final int countedItems;
  final int discrepancyItems;
  final int appliedItems;
  final List<StockTakeHistoryLine> lines;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_name': sessionName,
      'started_at': startedAtIso,
      'applied_at': appliedAtIso,
      'total_products': totalProducts,
      'counted_items': countedItems,
      'discrepancy_items': discrepancyItems,
      'applied_items': appliedItems,
      'lines': lines.map((line) => line.toMap()).toList(),
    };
  }

  factory StockTakeHistoryEntry.fromMap(Map<String, dynamic> map) {
    final rawLines = map['lines'] as List<dynamic>? ?? const <dynamic>[];

    return StockTakeHistoryEntry(
      id: (map['id'] ?? '').toString(),
      sessionName: (map['session_name'] ?? 'Stock Take Session').toString(),
      startedAtIso: (map['started_at'] ?? '').toString(),
      appliedAtIso: (map['applied_at'] ?? '').toString(),
      totalProducts: int.tryParse(map['total_products'].toString()) ?? 0,
      countedItems: int.tryParse(map['counted_items'].toString()) ?? 0,
      discrepancyItems: int.tryParse(map['discrepancy_items'].toString()) ?? 0,
      appliedItems: int.tryParse(map['applied_items'].toString()) ?? 0,
      lines: rawLines
          .whereType<Map>()
          .map(
            (item) => StockTakeHistoryLine.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class StockTakeSessionService {
  static const String _draftKey = 'admin_stock_take_draft_v1';
  static const String _historyKey = 'admin_stock_take_history_v1';
  static const int _maxHistoryEntries = 30;

  Future<StockTakeDraft?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return StockTakeDraft.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(StockTakeDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, json.encode(draft.toMap()));
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<List<StockTakeHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return <StockTakeHistoryEntry>[];

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => StockTakeHistoryEntry.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return <StockTakeHistoryEntry>[];
    }
  }

  Future<void> addHistoryEntry(StockTakeHistoryEntry entry) async {
    final history = await loadHistory();
    final next = <StockTakeHistoryEntry>[entry, ...history]
        .take(_maxHistoryEntries)
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      json.encode(next.map((item) => item.toMap()).toList()),
    );
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
