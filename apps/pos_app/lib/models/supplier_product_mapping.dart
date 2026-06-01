class SupplierProductMapping {
  final int? id;
  final String barcode;
  final String productName;
  final String? productNameSi;
  final int supplierId;
  final String supplierName;
  final bool isPreferred;
  final double defaultUnitCost;
  final int minimumOrderQuantity;
  final int packSize;
  final int leadTimeDays;
  final String note;
  final String updatedAt;

  const SupplierProductMapping({
    this.id,
    required this.barcode,
    required this.productName,
    this.productNameSi,
    required this.supplierId,
    required this.supplierName,
    this.isPreferred = true,
    this.defaultUnitCost = 0,
    this.minimumOrderQuantity = 1,
    this.packSize = 1,
    this.leadTimeDays = 0,
    this.note = '',
    required this.updatedAt,
  });

  factory SupplierProductMapping.fromMap(Map<String, dynamic> map) {
    return SupplierProductMapping(
      id: (map['id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      productNameSi: map['product_name_si']?.toString(),
      supplierId: ((map['supplier_id'] as num?) ?? 0).toInt(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      isPreferred:
          ((map['is_preferred'] as num?) ?? 0).toInt() == 1 ||
          map['is_preferred'] == true,
      defaultUnitCost: ((map['default_unit_cost'] as num?) ?? 0).toDouble(),
      minimumOrderQuantity: ((map['minimum_order_quantity'] as num?) ?? 1)
          .toInt(),
      packSize: ((map['pack_size'] as num?) ?? 1).toInt(),
      leadTimeDays: ((map['lead_time_days'] as num?) ?? 0).toInt(),
      note: (map['note'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'barcode': barcode,
      'product_name': productName,
      'product_name_si': productNameSi,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'is_preferred': isPreferred ? 1 : 0,
      'default_unit_cost': defaultUnitCost,
      'minimum_order_quantity': minimumOrderQuantity,
      'pack_size': packSize,
      'lead_time_days': leadTimeDays,
      'note': note,
      'updated_at': updatedAt,
    };

    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  SupplierProductMapping copyWith({
    int? id,
    String? barcode,
    String? productName,
    String? productNameSi,
    int? supplierId,
    String? supplierName,
    bool? isPreferred,
    double? defaultUnitCost,
    int? minimumOrderQuantity,
    int? packSize,
    int? leadTimeDays,
    String? note,
    String? updatedAt,
  }) {
    return SupplierProductMapping(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      productName: productName ?? this.productName,
      productNameSi: productNameSi ?? this.productNameSi,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      isPreferred: isPreferred ?? this.isPreferred,
      defaultUnitCost: defaultUnitCost ?? this.defaultUnitCost,
      minimumOrderQuantity: minimumOrderQuantity ?? this.minimumOrderQuantity,
      packSize: packSize ?? this.packSize,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
