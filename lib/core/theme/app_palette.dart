import 'package:flutter/material.dart';

/// Semantic colors transcribed from the approved light PDF and dark references.
abstract final class AppPalette {
  static const navy = Color(0xFF173B57);
  static const orange = Color(0xFFF4AE45);
  static const cream = Color(0xFFFCF8EF);
  static const cardBlue = Color(0xFFD6E6F2);
  static const inputCream = Color(0xFFFAE8CE);
  static const dark = Color(0xFF202020);
  static const darkCard = Color(0xFF3A3A3A);
  static const darkIncomingMessage = Color(0xFF5C5C5C);
  static const lightText = Color(0xFFF2F7FB);
  static const ink = Color(0xFF1D1D1D);
  static TextStyle inputTextStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(color: navy);
}
