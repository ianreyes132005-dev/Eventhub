import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/event_audience.dart';

// "Who can register" on the organizer's event form — the web dialog and the
// app screen use this one picker, so the two always offer the same choices:
//
//   [All students]          [Junior High · Grades 7–10]
//   [Senior High · 11–12]   [Specific grades]
//   Junior High  7 8 9 10     Senior High  11 12      ← Specific grades only
//   Strands  All strands  HUMSS  GAS  STEM            ← with Grade 11 or 12
//
// The form keeps the AudienceChoice; this only shows it and reports taps.

/// The form's colours (WebTk on the web, AppTk in the app).
class AudiencePickerColors {
  const AudiencePickerColors({
    required this.dark,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
  });

  final bool dark;

  /// A choice that isn't picked.
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
}

class AudiencePicker extends StatelessWidget {
  const AudiencePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.colors,
    this.touch = false,
  });

  final AudienceChoice value;
  final ValueChanged<AudienceChoice> onChanged;
  final AudiencePickerColors colors;

  /// Phones: taller choices, for fingers.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final custom = v.preset == AudiencePreset.custom;
    Widget caption(String text) => Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              fontWeight: FontWeight.w600, color: colors.muted)),
        );
    Widget small(String label, bool selected, VoidCallback onTap, {String? semanticLabel}) =>
        _AudienceChip(label: label, selected: selected, onTap: onTap, colors: colors,
            dense: true, touch: touch, semanticLabel: semanticLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The four groups as an even 2 × 2 grid; on a narrow screen each
        // choice puts its grades on a second line.
        LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - 8) / 2;
          final stacked = w < 230;
          final h = stacked ? (touch ? 58.0 : 52.0) : (touch ? 48.0 : 42.0);
          Widget group(String label, String? sub, AudiencePreset p) => SizedBox(
                width: w,
                height: h,
                child: _AudienceChip(
                  label: label,
                  sub: sub,
                  stacked: stacked,
                  selected: v.preset == p,
                  onTap: () => onChanged(v.choose(p)),
                  colors: colors,
                  touch: touch,
                ),
              );
          return Wrap(spacing: 8, runSpacing: 8, children: [
            group('All students', null, AudiencePreset.everyone),
            group('Junior High', 'Grades 7–10', AudiencePreset.juniorHigh),
            group('Senior High', 'Grades 11–12', AudiencePreset.seniorHigh),
            group('Specific grades', null, AudiencePreset.custom),
          ]);
        }),
        if (custom) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              caption('Junior High'),
              for (final g in kJuniorHighGrades)
                small('$g', v.grades.contains(g), () => onChanged(v.toggleGrade(g)),
                    semanticLabel: 'Grade $g'),
              const SizedBox(width: 10),
              caption('Senior High'),
              for (final g in kSeniorHighGrades)
                small('$g', v.grades.contains(g), () => onChanged(v.toggleGrade(g)),
                    semanticLabel: 'Grade $g'),
            ],
          ),
        ],
        if (v.showsStrands) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              caption('Strands'),
              small('All strands', v.strands.isEmpty, () => onChanged(v.allStrands())),
              for (final s in kShsStrands)
                small(s, v.strands.contains(s), () => onChanged(v.toggleStrand(s))),
            ],
          ),
          if (v.mixesLevels)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Strands only narrow the Senior High grades.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: colors.muted)),
            ),
        ],
      ],
    );
  }
}

/// One choice: a group, a grade or a strand. Picked = gold outline and a
/// check. [semanticLabel] replaces a short label for screen readers
/// ("Grade 7" for "7").
class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.touch,
    this.sub,
    this.stacked = false,
    this.dense = false,
    this.semanticLabel,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final AudiencePickerColors colors;
  final bool touch;
  final bool stacked;
  final bool dense;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Gold text that reads on a light card (4.9:1); plain gold on dark.
    final accent = colors.dark ? kGold : const Color(0xFF8A6516);
    final radius = BorderRadius.circular(10);
    final labelStyle = TextStyle(fontFamily: 'Poppins',
        fontSize: dense ? 12 : 12.5,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected ? accent : colors.text);
    final subStyle = TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
        fontWeight: FontWeight.w400, color: colors.muted);
    final check = selected
        ? [Icon(Icons.check_rounded, size: 14, color: accent), const SizedBox(width: 4)]
        : const <Widget>[];

    final Widget content = stacked && sub != null
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                ...check,
                Flexible(child: Text(label, style: labelStyle,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 1),
              Text(sub!, style: subStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )
        : Row(mainAxisSize: MainAxisSize.min, children: [
            ...check,
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label, style: labelStyle),
                  if (sub != null) TextSpan(text: '  $sub', style: subStyle),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: selected ? kGold.withValues(alpha: colors.dark ? 0.16 : 0.10) : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? kGold : colors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            // Phones: a grade or strand is still a comfortable tap.
            constraints: BoxConstraints(
                minHeight: dense ? (touch ? 40 : 32) : 0,
                minWidth: dense ? (touch ? 44 : 36) : 0),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 6 : 8),
              child: dense ? Center(widthFactor: 1, child: content) : content,
            ),
          ),
        ),
      ),
    );
  }
}
