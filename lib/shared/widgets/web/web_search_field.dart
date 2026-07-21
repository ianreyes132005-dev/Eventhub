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
  Widget build(BuildContext context) {
    final dark      = Theme.of(context).brightness == Brightness.dark;
    final textCol   = dark ? const Color(0xFFE7EAEE) : kText;
    final mutedCol  = dark ? const Color(0xFF666E7D) : kMuted;
    final borderCol = dark ? const Color(0xFF232833) : kCardBorder;
    final fillCol   = dark ? const Color(0xFF0E1116) : Colors.white;
    return SizedBox(
      width: width,
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: textCol),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: mutedCol),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: mutedCol),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderCol),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderCol),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGold, width: 1.5),
          ),
          filled: true,
          fillColor: fillCol,
        ),
      ),
    );
  }
}
