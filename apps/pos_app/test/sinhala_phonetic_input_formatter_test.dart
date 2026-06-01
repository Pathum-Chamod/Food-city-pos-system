import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/sinhala_phonetic_input_formatter.dart';

void main() {
  test('transliterates common Singlish product-name words', () {
    expect(
      SinhalaPhoneticTransliterator.transliterate('kiri piti'),
      '\u0D9A\u0DD2\u0DBB\u0DD2 \u0DB4\u0DD2\u0DA7\u0DD2',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('amma'),
      '\u0D85\u0DB8\u0DCA\u0DB8',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('pol'),
      '\u0DB4\u0DDC\u0DBD\u0DCA',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('paang'),
      '\u0DB4\u0DCF\u0D82',
    );
  });

  test('keeps compact measurement values in Latin text', () {
    expect(
      SinhalaPhoneticTransliterator.transliterate('kiri piti 100g'),
      '\u0D9A\u0DD2\u0DBB\u0DD2 \u0DB4\u0DD2\u0DA7\u0DD2 100g',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('wathura 100L'),
      '\u0DC0\u0DAD\u0DD4\u0DBB 100L',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('100 1.5kg 10pcs'),
      '100 1.5kg 10pcs',
    );
    expect(
      SinhalaPhoneticTransliterator.transliterate('250ml 2pack'),
      '250ml 2pack',
    );
  });

  test('supports Helakuru-style special Sinhala letters', () {
    expect(SinhalaPhoneticTransliterator.transliterate('chha'), '\u0DA1');
    expect(SinhalaPhoneticTransliterator.transliterate('zdha'), '\u0DB3');
    expect(SinhalaPhoneticTransliterator.transliterate('nnga'), '\u0D9F');
  });

  test('formats live typing while keeping the roman buffer editable', () {
    final formatter = SinhalaPhoneticInputFormatter();
    var value = const TextEditingValue();

    for (final char in 'kiri'.split('')) {
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: value.text + char,
          selection: TextSelection.collapsed(offset: value.text.length + 1),
        ),
      );
    }

    expect(value.text, '\u0D9A\u0DD2\u0DBB\u0DD2');

    value = formatter.formatEditUpdate(
      value,
      TextEditingValue(
        text: value.text.substring(0, value.text.length - 1),
        selection: TextSelection.collapsed(offset: value.text.length - 1),
      ),
    );

    expect(value.text, '\u0D9A\u0DD2\u0DBB\u0DCA');
  });
}
