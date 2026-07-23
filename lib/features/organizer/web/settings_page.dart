import 'package:flutter/material.dart';
import 'web_shared.dart';
import 'profile_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Settings page — now just hosts Profile directly.
//
// Dark/light theme and About EventHub both moved onto the Profile page itself
// (Preferences section); sidebar color/variant customization was removed as a
// user-facing setting once the sidebar standardized on the Pure White design.
// With only one destination left, there's no tab bar to switch between — this
// widget is a thin pass-through to WebProfilePage (which owns its own single
// scrollable and page header).
// ─────────────────────────────────────────────────────────────────────────────

class WebSettingsPage extends StatelessWidget {
  final String?  orgId;
  final String?  name;
  final String?  email;
  final String?  organization;
  final void Function(String)?        onPhotoUpdated;
  final void Function(OrganizerPage)? onNavigate;

  const WebSettingsPage({
    super.key,
    this.orgId,
    this.name,
    this.email,
    this.organization,
    this.onPhotoUpdated,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) => WebProfilePage(
    orgId:        orgId,
    name:         name,
    email:        email,
    organization: organization,
    onPhotoUpdated: onPhotoUpdated,
    onNavigate:     onNavigate,
  );
}
