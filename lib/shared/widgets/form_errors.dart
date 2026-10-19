import 'package:flutter/material.dart';

// Inline form-error pieces shared by the organizer event forms (web + mobile).
// Red is reserved for errors on these forms — a field that is merely filled
// in never uses it.

/// Error red, readable on light and dark backgrounds.
Color formErrorColor(bool dark) => dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

/// Red message under a field. Announced by screen readers when it appears.
class FormFieldError extends StatelessWidget {
  final String message;
  final bool   dark;
  const FormFieldError(this.message, {super.key, required this.dark});

  @override
  Widget build(BuildContext context) {
    final c = formErrorColor(dark);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, left: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 14, color: c),
          ),
          const SizedBox(width: 5),
          Expanded(child: Text(message, style: TextStyle(fontFamily: 'Poppins',
              fontSize: 11.5, fontWeight: FontWeight.w500, color: c, height: 1.35))),
        ]),
      ),
    );
  }
}

/// "2 to fix" tag for a section header.
class FormSectionErrorPill extends StatelessWidget {
  final int  count;
  final bool dark;
  const FormSectionErrorPill({super.key, required this.count, required this.dark});

  @override
  Widget build(BuildContext context) {
    final c = formErrorColor(dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count to fix', style: TextStyle(fontFamily: 'Poppins',
          fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Summary at the top of the form: what still needs attention, each item
/// tappable to jump to the field.
class FormErrorSummary<T> extends StatelessWidget {
  final Map<T, String> errors;
  final Map<T, String> labels;
  final ValueChanged<T> onTap;
  final bool dark;
  final Color textColor;
  const FormErrorSummary({
    super.key,
    required this.errors,
    required this.labels,
    required this.onTap,
    required this.dark,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = formErrorColor(dark);
    final n = errors.length;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: dark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.error_outline_rounded, size: 17, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(
              n == 1 ? '1 field needs your attention' : '$n fields need your attention',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700, color: textColor))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in errors.keys)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onTap(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.withValues(alpha: 0.45)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(labels[f] ?? '$f', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_downward_rounded, size: 12, color: c),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
