import 'package:shared/shared.dart';

import '../providers/language_provider.dart';

class ProductNameHelper {
  static String displayName(Product product, AppLanguage language) {
    final si = product.nameSi?.trim();
    if (language == AppLanguage.sinhala && si != null && si.isNotEmpty) {
      return si;
    }

    return englishName(product);
  }

  static String englishName(Product product) {
    final en = product.name.trim();
    if (en.isNotEmpty) return en;

    final barcode = product.barcode.trim();
    if (barcode.isNotEmpty) return barcode;

    return 'Unknown product';
  }

  static String displayNameFromParts({
    required String? englishName,
    String? sinhalaName,
    String? barcode,
    required AppLanguage language,
    String fallback = 'Unknown product',
  }) {
    final si = sinhalaName?.trim() ?? '';
    if (language == AppLanguage.sinhala && si.isNotEmpty) return si;

    final en = englishName?.trim() ?? '';
    if (en.isNotEmpty) return en;

    final code = barcode?.trim() ?? '';
    if (code.isNotEmpty) return code;

    return fallback;
  }

  static String displayNameFromMap(
    Map<dynamic, dynamic> row,
    AppLanguage language, {
    String englishKey = 'product_name',
    String sinhalaKey = 'product_name_si',
    String barcodeKey = 'barcode',
    String fallback = 'Unknown product',
  }) {
    return displayNameFromParts(
      englishName: row[englishKey]?.toString(),
      sinhalaName: row[sinhalaKey]?.toString(),
      barcode: row[barcodeKey]?.toString(),
      language: language,
      fallback: fallback,
    );
  }

  static bool matchesProduct(Product product, String input) {
    final query = input.trim();
    if (query.isEmpty) return true;

    final queryLower = query.toLowerCase();
    final english = product.name.toLowerCase();
    final sinhala = product.nameSi?.trim() ?? '';
    final barcode = product.barcode.trim();

    return barcode.contains(query) ||
        english.contains(queryLower) ||
        sinhala.contains(query);
  }
}
