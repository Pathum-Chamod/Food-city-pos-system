import '../providers/language_provider.dart';

class ReceiptTextUtils {
  const ReceiptTextUtils._();

  static bool containsSinhala(String value) {
    return value.runes.any((code) => code >= 0x0D80 && code <= 0x0DFF);
  }

  static bool containsEscPosUnsafeText(String value) {
    return value.runes.any((code) => code > 0x00FF);
  }

  static bool receiptNeedsUnicodePath({
    required AppLanguage language,
    required List<Map<String, dynamic>> items,
  }) {
    if (language == AppLanguage.sinhala) return true;

    return items.any((item) {
      return containsSinhala((item['name'] ?? '').toString());
    });
  }

  static bool receiptContainsSinhala({
    required List<Map<String, dynamic>> items,
    Iterable<String> extraText = const [],
  }) {
    return extraText.any(containsSinhala) ||
        items.any((item) {
          return containsSinhala((item['name'] ?? '').toString());
        });
  }

  static String? firstEscPosUnsafeText({
    required List<Map<String, dynamic>> items,
    Iterable<String> extraText = const [],
  }) {
    for (final value in extraText) {
      if (containsEscPosUnsafeText(value)) return value;
    }

    for (final item in items) {
      final value = (item['name'] ?? '').toString();
      if (containsEscPosUnsafeText(value)) return value;
    }

    return null;
  }
}
