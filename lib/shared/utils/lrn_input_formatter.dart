import 'package:flutter/services.dart';

/// Formats a 12-digit LRN while typing: `123456 - 26 - 0042`.
/// Only digits are kept; anything past 12 digits is dropped.
class LrnInputFormatter extends TextInputFormatter {
  const LrnInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = lrnDigits(newValue.text);
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buf    = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 6 || i == 8) buf.write(' - ');
      buf.write(capped[i]);
    }
    final out = buf.toString();
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Digits only — `'123456 - 26 - 0042'` → `'123456260042'`.
String lrnDigits(String s) => s.replaceAll(RegExp(r'\D'), '');
