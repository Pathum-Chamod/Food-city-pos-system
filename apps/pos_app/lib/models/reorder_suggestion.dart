import 'package:flutter/foundation.dart';

@immutable
class ReorderSuggestion {
  final String barcode;
  final String productName;
  final int currentStock;
  final int reorderLevel;
  final int targetStock;
  final int soldUnits30d;
  final double lastUnitCost;
  final int suggestedQuantity;

  const ReorderSuggestion({
    required this.barcode,
    required this.productName,
    required this.currentStock,
    required this.reorderLevel,
    required this.targetStock,
    required this.soldUnits30d,
    required this.lastUnitCost,
    required this.suggestedQuantity,
  });

  double get estimatedCost => suggestedQuantity * lastUnitCost;
  bool get isOutOfStock => currentStock <= 0;
  bool get isLowStock => currentStock > 0 && currentStock <= reorderLevel;
  bool get isHighDemand => soldUnits30d >= 20;

  factory ReorderSuggestion.fromMap(Map<dynamic, dynamic> map) {
    return ReorderSuggestion(
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      currentStock: (map['current_stock'] as num?)?.toInt() ?? 0,
      reorderLevel: (map['reorder_level'] as num?)?.toInt() ?? 10,
      targetStock: (map['target_stock'] as num?)?.toInt() ?? 30,
      soldUnits30d: (map['sold_units_30d'] as num?)?.toInt() ?? 0,
      lastUnitCost: ((map['last_unit_cost'] as num?) ?? 0).toDouble(),
      suggestedQuantity: (map['suggested_quantity'] as num?)?.toInt() ?? 0,
    );
  }
}
