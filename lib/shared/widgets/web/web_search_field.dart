import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String               hint;
  final ValueChanged<String> onChanged;
  final double               width;
  const WebSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.width = 240,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 40,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: kMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kGold, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
  );
}
