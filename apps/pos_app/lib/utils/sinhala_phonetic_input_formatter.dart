import 'package:flutter/services.dart';

class SinhalaPhoneticTransliterator {
  static const _anusvara = '\u0D82';
  static const _halant = '\u0DCA';
  static const _ga = '\u0D9C';

  static const _vowels = <_VowelToken>[
    _VowelToken('Aa', '\u0D88', '\u0DD1'),
    _VowelToken('/a)', '\u0D88', '\u0DD1'),
    _VowelToken('/a', '\u0D87', '\u0DD0'),
    _VowelToken('aa', '\u0D86', '\u0DCF'),
    _VowelToken('ae', '\u0D88', '\u0DD1'),
    _VowelToken('ii', '\u0D8A', '\u0DD3'),
    _VowelToken('ie', '\u0D8A', '\u0DD3'),
    _VowelToken('ee', '\u0D8A', '\u0DD3'),
    _VowelToken('uu', '\u0D8C', '\u0DD6'),
    _VowelToken('oo', '\u0D8C', '\u0DD6'),
    _VowelToken('ea', '\u0D92', '\u0DDA'),
    _VowelToken('ei', '\u0D92', '\u0DDA'),
    _VowelToken('oe', '\u0D95', '\u0DDD'),
    _VowelToken('au', '\u0D96', '\u0DDE'),
    _VowelToken('A', '\u0D87', '\u0DD0'),
    _VowelToken('I', '\u0D93', '\u0DDB'),
    _VowelToken('a', '\u0D85', ''),
    _VowelToken('i', '\u0D89', '\u0DD2'),
    _VowelToken('u', '\u0D8B', '\u0DD4'),
    _VowelToken('e', '\u0D91', '\u0DD9'),
    _VowelToken('o', '\u0D94', '\u0DDC'),
  ];

  static const _consonants = <_ConsonantToken>[
    _ConsonantToken('ksh', '\u0D9A\u0DCA\u0DC2'),
    _ConsonantToken('chh', '\u0DA1'),
    _ConsonantToken('nndh', '\u0DB3'),
    _ConsonantToken('nnd', '\u0DAC'),
    _ConsonantToken('nng', '\u0D9F'),
    _ConsonantToken('zdh', '\u0DB3'),
    _ConsonantToken('zd', '\u0DAC'),
    _ConsonantToken('kh', '\u0D9B'),
    _ConsonantToken('gh', '\u0D9D'),
    _ConsonantToken('ch', '\u0DA0'),
    _ConsonantToken('sh', '\u0DC1'),
    _ConsonantToken('th', '\u0DAD'),
    _ConsonantToken('dh', '\u0DAF'),
    _ConsonantToken('ph', '\u0DB5'),
    _ConsonantToken('bh', '\u0DB7'),
    _ConsonantToken('gn', '\u0DA5'),
    _ConsonantToken('ny', '\u0DA4'),
    _ConsonantToken('x', '\u0D9A\u0DCA\u0DC2'),
    _ConsonantToken('K', '\u0D9B'),
    _ConsonantToken('G', '\u0D9D'),
    _ConsonantToken('T', '\u0DA7'),
    _ConsonantToken('D', '\u0DA9'),
    _ConsonantToken('N', '\u0DAB'),
    _ConsonantToken('L', '\u0DC5'),
    _ConsonantToken('S', '\u0DC2'),
    _ConsonantToken('k', '\u0D9A'),
    _ConsonantToken('g', '\u0D9C'),
    _ConsonantToken('c', '\u0DA0'),
    _ConsonantToken('j', '\u0DA2'),
    _ConsonantToken('t', '\u0DA7'),
    _ConsonantToken('d', '\u0DA9'),
    _ConsonantToken('n', '\u0DB1'),
    _ConsonantToken('p', '\u0DB4'),
    _ConsonantToken('b', '\u0DB6'),
    _ConsonantToken('m', '\u0DB8'),
    _ConsonantToken('y', '\u0DBA'),
    _ConsonantToken('r', '\u0DBB'),
    _ConsonantToken('l', '\u0DBD'),
    _ConsonantToken('v', '\u0DC0'),
    _ConsonantToken('w', '\u0DC0'),
    _ConsonantToken('s', '\u0DC3'),
    _ConsonantToken('h', '\u0DC4'),
    _ConsonantToken('f', '\u0DC6'),
  ];

  static String transliterate(String input) {
    final output = StringBuffer();
    var index = 0;

    while (index < input.length) {
      final measuredValue = _matchMeasuredValue(input, index);
      if (measuredValue != null) {
        output.write(measuredValue);
        index += measuredValue.length;
        continue;
      }

      final vowel = _matchVowel(input, index);
      if (vowel != null) {
        output.write(vowel.independent);
        index += vowel.pattern.length;
        continue;
      }

      if (input.startsWith('ng', index)) {
        final nextVowel = _matchVowel(input, index + 2);
        if (nextVowel == null) {
          output.write(_anusvara);
          index += 2;
        } else {
          output
            ..write(_anusvara)
            ..write(_ga)
            ..write(nextVowel.sign);
          index += 2 + nextVowel.pattern.length;
        }
        continue;
      }

      final consonant = _matchConsonant(input, index);
      if (consonant != null) {
        final nextIndex = index + consonant.pattern.length;
        final nextVowel = _matchVowel(input, nextIndex);
        output.write(consonant.sinhala);
        if (nextVowel != null) {
          output.write(nextVowel.sign);
          index = nextIndex + nextVowel.pattern.length;
        } else {
          output.write(_halant);
          index = nextIndex;
        }
        continue;
      }

      output.write(input[index]);
      index += 1;
    }

    return output.toString();
  }

  static _VowelToken? _matchVowel(String input, int index) {
    for (final vowel in _vowels) {
      if (input.startsWith(vowel.pattern, index)) return vowel;
    }
    return null;
  }

  static _ConsonantToken? _matchConsonant(String input, int index) {
    for (final consonant in _consonants) {
      if (input.startsWith(consonant.pattern, index)) return consonant;
    }
    return null;
  }

  static String? _matchMeasuredValue(String input, int index) {
    if (index >= input.length || !_isDigit(input.codeUnitAt(index))) {
      return null;
    }

    var end = index;
    while (end < input.length && _isDigit(input.codeUnitAt(end))) {
      end += 1;
    }

    if (end < input.length &&
        input.codeUnitAt(end) == 0x2E &&
        end + 1 < input.length &&
        _isDigit(input.codeUnitAt(end + 1))) {
      end += 1;
      while (end < input.length && _isDigit(input.codeUnitAt(end))) {
        end += 1;
      }
    }

    final unitStart = end;
    while (end < input.length && _isAsciiLetter(input.codeUnitAt(end))) {
      end += 1;
    }

    if (unitStart == end) return input.substring(index, end);

    final unit = input.substring(unitStart, end).toLowerCase();
    const units = {
      'g',
      'kg',
      'mg',
      'l',
      'ml',
      'm',
      'cm',
      'mm',
      'pcs',
      'pc',
      'pkt',
      'pack',
      'x',
    };

    if (!units.contains(unit)) return input.substring(index, unitStart);
    return input.substring(index, end);
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  static bool _isAsciiLetter(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
  }
}

class SinhalaPhoneticInputFormatter extends TextInputFormatter {
  String _rawText = '';
  String _displayText = '';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_displayText != oldValue.text) {
      _rawText = oldValue.text;
      _displayText = oldValue.text;
    }

    _rawText = _applyEditToRawText(oldValue.text, newValue.text);
    _displayText = SinhalaPhoneticTransliterator.transliterate(_rawText);

    return TextEditingValue(
      text: _displayText,
      selection: TextSelection.collapsed(offset: _displayText.length),
    );
  }

  String _applyEditToRawText(String oldText, String newText) {
    if (newText == oldText) return _rawText;

    if (newText.startsWith(oldText)) {
      return _rawText + newText.substring(oldText.length);
    }

    if (oldText.startsWith(newText) && newText.length < oldText.length) {
      if (_rawText.isEmpty) return '';
      return _rawText.substring(0, _rawText.length - 1);
    }

    return newText;
  }
}

class _VowelToken {
  const _VowelToken(this.pattern, this.independent, this.sign);

  final String pattern;
  final String independent;
  final String sign;
}

class _ConsonantToken {
  const _ConsonantToken(this.pattern, this.sinhala);

  final String pattern;
  final String sinhala;
}
