import 'package:shared/shared.dart';

class ProductNameHelper {
  const ProductNameHelper._();

  static String primary(Product product) => product.name;

  static String? sinhala(Product product) {
    final value = product.nameSi?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool matches(Product product, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    return product.name.toLowerCase().contains(normalized) ||
        (product.nameSi?.toLowerCase().contains(normalized) ?? false) ||
        product.barcode.toLowerCase().contains(normalized);
  }

  static String fromRow(Map<String, dynamic> row) {
    final english = (row['product_name'] ?? row['name'] ?? '')
        .toString()
        .trim();
    return english.isEmpty ? 'Unknown' : english;
  }

  static String? sinhalaFromRow(Map<String, dynamic> row) {
    final value = (row['product_name_si'] ?? row['name_si'] ?? '')
        .toString()
        .trim();
    return value.isEmpty ? null : value;
  }
}
