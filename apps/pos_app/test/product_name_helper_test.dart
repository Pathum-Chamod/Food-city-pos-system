import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/providers/language_provider.dart';
import 'package:pos_app/services/receipt_text_utils.dart';
import 'package:pos_app/utils/product_name_helper.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Product product({
    String barcode = '4792011001234',
    String name = 'Anchor Milk Powder 400g',
    String? nameSi = 'ඇන්කර් කිරිපිටි 400g',
  }) {
    return Product(
      barcode: barcode,
      name: name,
      nameSi: nameSi,
      sellingPrice: 1100,
      stock: 50,
      updatedAt: '2026-05-26T00:00:00.000',
    );
  }

  test('Product maps Sinhala product names safely', () {
    final item = product();

    expect(item.toMap()['name_si'], 'ඇන්කර් කිරිපිටි 400g');
    expect(Product.fromMap(item.toMap()).nameSi, 'ඇන්කර් කිරිපිටි 400g');
  });

  test('displayName uses Sinhala only when selected and available', () {
    final item = product();

    expect(
      ProductNameHelper.displayName(item, AppLanguage.english),
      'Anchor Milk Powder 400g',
    );
    expect(
      ProductNameHelper.displayName(item, AppLanguage.sinhala),
      'ඇන්කර් කිරිපිටි 400g',
    );
    expect(
      ProductNameHelper.displayName(product(nameSi: ''), AppLanguage.sinhala),
      'Anchor Milk Powder 400g',
    );
  });

  test('matchesProduct searches barcode, English name, and Sinhala name', () {
    final item = product();

    expect(ProductNameHelper.matchesProduct(item, '479201'), isTrue);
    expect(ProductNameHelper.matchesProduct(item, 'anchor'), isTrue);
    expect(ProductNameHelper.matchesProduct(item, 'ඇන්කර්'), isTrue);
    expect(ProductNameHelper.matchesProduct(item, 'missing'), isFalse);
  });
  test('displayNameFromMap uses Sinhala snapshot with barcode fallback', () {
    final row = {
      'product_name': 'Anchor Milk Powder 400g',
      'product_name_si': 'Sinhala snapshot',
      'barcode': '4792011001234',
    };

    expect(
      ProductNameHelper.displayNameFromMap(row, AppLanguage.english),
      'Anchor Milk Powder 400g',
    );
    expect(
      ProductNameHelper.displayNameFromMap(row, AppLanguage.sinhala),
      'Sinhala snapshot',
    );
    expect(
      ProductNameHelper.displayNameFromMap({
        'product_name': '',
        'product_name_si': '',
        'barcode': 'ABC123',
      }, AppLanguage.sinhala),
      'ABC123',
    );
  });

  test('receipt text utils detect Sinhala and protect ESC/POS output', () {
    final sinhalaName = String.fromCharCodes([
      0x0D87,
      0x0DB1,
      0x0DCA,
      0x0D9A,
      0x0DBB,
      0x0DCA,
    ]);
    final receiptItems = [
      {
        'name': sinhalaName,
        'englishName': 'Anchor',
        'sinhalaName': sinhalaName,
      },
    ];

    expect(ReceiptTextUtils.containsSinhala(sinhalaName), isTrue);
    expect(
      ReceiptTextUtils.receiptNeedsUnicodePath(
        language: AppLanguage.english,
        items: receiptItems,
      ),
      isTrue,
    );
    expect(
      ReceiptTextUtils.firstEscPosUnsafeText(items: receiptItems),
      sinhalaName,
    );
    expect(
      ReceiptTextUtils.receiptNeedsUnicodePath(
        language: AppLanguage.sinhala,
        items: const [
          {'name': 'Anchor', 'englishName': 'Anchor'},
        ],
      ),
      isTrue,
    );
    expect(
      ReceiptTextUtils.receiptNeedsUnicodePath(
        language: AppLanguage.english,
        items: [
          {'name': 'Anchor', 'sinhalaName': sinhalaName},
        ],
      ),
      isFalse,
    );
  });

  test('LanguageProvider persists and restores selected language', () async {
    SharedPreferences.setMockInitialValues({});

    final provider = LanguageProvider();
    await provider.load();
    expect(provider.language, AppLanguage.english);

    await provider.setLanguage(AppLanguage.sinhala);
    expect(provider.language, AppLanguage.sinhala);

    final restored = LanguageProvider();
    await restored.load();
    expect(restored.language, AppLanguage.sinhala);

    await restored.toggle();
    expect(restored.language, AppLanguage.english);
  });
}
