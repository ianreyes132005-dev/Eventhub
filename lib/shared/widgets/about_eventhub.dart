import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

// About EventHub — what the student app, the organizer app and the organizer
// web portal say about EventHub, kept here once (each keeps its own dialog
// frame). Keep it true to the app, like the Terms
// (features/auth/terms_content.dart).

/// The school's official name.
const kSchoolName = 'J-Jireh School, Inc.';

/// Who built EventHub, as the team gave their names.
const kDevelopers = ['Reyes, Ian', 'Jamallul, Trisha', 'Ammad, Ainie'];

/// "Version 1.0.7 (build 8)": the build number says exactly which APK
/// someone has.
String aboutVersionLabel(String version, String build) {
  if (version.isEmpty || version == '—') return 'Version —';
  return build.isEmpty || build == version
      ? 'Version $version'
      : 'Version $version (build $build)';
}

/// Who's reading: what EventHub does for them, and where it runs.
enum AboutAudience { student, organizer }

/// The About text, info rows, links to the Terms and the Privacy Policy, and
/// who developed it. [onOpenTerms] / [onOpenPrivacy] open the same dialogs as
/// the sign-in screen. (The contact is the school administrator only, and
/// there's no open-source licenses link or Updates box — the user asked to
/// remove them.)
class AboutEventHubBody extends StatelessWidget {
  const AboutEventHubBody({
    super.key,
    required this.audience,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    required this.textColor,
    required this.mutedColor,
    required this.dividerColor,
    this.centered = false,
    this.fontSize = 11.5,
  });

  final AboutAudience audience;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final Color textColor;
  final Color mutedColor;
  final Color dividerColor;
  /// The app dialogs center their text; the web one lines it up left.
  final bool centered;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final student = audience == AboutAudience.student;
    final align = centered ? TextAlign.center : TextAlign.start;
    final body = TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      height: 1.6,
      color: mutedColor,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // kSchoolName ends in "Inc.", which also ends the sentence.
        Text(
          student
              ? 'The official event management platform of $kSchoolName '
                  'Find school events, register, show your QR ticket at '
                  'check-in, and follow your attendance, all in one place.'
              : 'The official event management platform of $kSchoolName '
                  'Create events, run check-in, review registrations, post '
                  'announcements, and track attendance, all in one place.',
          textAlign: align,
          style: body,
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: dividerColor),
        const SizedBox(height: 14),
        _info(Icons.school_rounded, 'School', kSchoolName),
        _info(
          Icons.devices_rounded,
          'Available on',
          student ? 'Android app' : 'Android app · web portal',
        ),
        _info(Icons.build_rounded, 'Built with', 'Flutter · Dart · Supabase'),
        _info(Icons.support_agent_rounded, 'Contact', 'School administrator'),
        const SizedBox(height: 4),
        Divider(height: 1, color: dividerColor),
        const SizedBox(height: 4),
        _link(Icons.gavel_rounded, 'Terms and Conditions', onOpenTerms),
        _link(Icons.privacy_tip_outlined, 'Privacy Policy', onOpenPrivacy),
        const SizedBox(height: 16),
        Text(
          'Developed by',
          textAlign: align,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 4),
        for (final name in kDevelopers)
          Text(name, textAlign: align, style: body.copyWith(height: 1.5)),
      ],
    );
  }

  Widget _info(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: kGold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$label  ',
                  style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
                ),
                TextSpan(text: value, style: TextStyle(color: mutedColor)),
              ]),
              style: TextStyle(fontFamily: 'Poppins', fontSize: fontSize, height: 1.45),
            ),
          ),
        ),
      ],
    ),
  );

  // Its own see-through Material, so the tap highlight shows on top of the
  // dialog's card colour.
  Widget _link(IconData icon, String label, VoidCallback onTap) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: kGold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: fontSize + 0.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: mutedColor),
          ],
        ),
      ),
    ),
  );
}
