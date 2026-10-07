import 'package:flutter/material.dart';

const eventHubTerms = <({IconData icon, String title, String body})>[
  (
    icon: Icons.info_outline_rounded,
    title: 'About EventHub',
    body: 'J-Jireh EventHub is a school event management system. It provides students with event discovery, registration, QR tickets, attendance updates, and announcements. It also provides authorized organizers with event and registration management tools, and administrators with account and system oversight tools.',
  ),
  (
    icon: Icons.handshake_outlined,
    title: 'Acceptance and scope',
    body: 'By signing in to or using EventHub, you agree to these Terms and Conditions. These terms apply to the EventHub mobile application, web portal, and the features made available through your account. If you do not agree, do not access or use the system.',
  ),
  (
    icon: Icons.school_outlined,
    title: 'Eligibility and account provisioning',
    body: 'EventHub is intended for currently enrolled students and school personnel authorized by J-Jireh. Accounts are provisioned by an administrator; users cannot create their own accounts through the app. Your access and available features depend on the role assigned to your account.',
  ),
  (
    icon: Icons.manage_accounts_outlined,
    title: 'Account security',
    body: 'Keep your sign-in details confidential, use your own account, and sign out when using a shared device. You are responsible for activity performed through your account. Contact a school administrator promptly if you suspect that your credentials have been exposed or your account has been used without permission.',
  ),
  (
    icon: Icons.event_available_outlined,
    title: 'Student event use',
    body: 'Students may use EventHub to browse available school events, review event information, register where registration is open, view their registrations, and receive event announcements. Event details, registration availability, capacity, and attendance requirements are determined by the school or event organizer. A registration is subject to the event’s published requirements and does not override them.',
  ),
  (
    icon: Icons.qr_code_2_rounded,
    title: 'QR tickets and attendance',
    body: 'EventHub may issue a QR code associated with a student’s event registration. Present only your own ticket for check-in. Do not copy, share, alter, or attempt to reuse another person’s QR code. Organizers may scan the code to locate a registration and record or continue the event check-in process. The app’s displayed status may change as the organizer processes the check-in.',
  ),
  (
    icon: Icons.face_outlined,
    title: 'Selfie check-in',
    body: 'An organizer may request a selfie as part of an event’s identity verification process. Submit a genuine image of yourself when requested and follow the school’s event instructions. Selfie images and related registration information are used for the check-in workflow and are available to authorized personnel through the system. Do not upload another person’s image or an unrelated, misleading, or inappropriate image.',
  ),
  (
    icon: Icons.admin_panel_settings_outlined,
    title: 'Organizer and administrator tools',
    body: 'Authorized organizers may create and manage events, review registrations, update registration or check-in statuses, send event announcements, and view attendance information. Administrators may manage accounts and review system-wide information. Use these tools only for your authorized school responsibilities and only for their intended event-management purposes.',
  ),
  (
    icon: Icons.campaign_outlined,
    title: 'Announcements and AI assistant',
    body: 'EventHub may display school or event announcements. Check the event details and follow any instructions provided by the school or organizer. The organizer web portal may also provide an AI assistant for event-related questions. AI responses can be incomplete or inaccurate and are provided as assistance, not as an official school decision. Do not enter passwords or sensitive personal information into the assistant.',
  ),
  (
    icon: Icons.rule_outlined,
    title: 'Acceptable use',
    body: 'Use EventHub only for legitimate school and event activities. You must not access another person’s account or data, interfere with the service, bypass role permissions or check-in controls, submit false registration information, misuse QR tickets, upload prohibited content, or use the system for unlawful, commercial, or unrelated purposes.',
  ),
  (
    icon: Icons.storage_outlined,
    title: 'Information and system operation',
    body: 'EventHub processes account, profile, event registration, attendance, announcement, and check-in information to provide its features. The system uses Supabase services for authentication and data storage. Access to information is controlled by account roles and the system’s configured permissions. Questions about school data practices should be directed to a school administrator.',
  ),
  (
    icon: Icons.sync_rounded,
    title: 'Availability and changes',
    body: 'The school may update, pause, or discontinue a feature for maintenance, operational, or security reasons. EventHub may not always be available or display information without delay. These terms and the system may be updated as the service changes. Continued use after updated terms are made available constitutes acceptance of the revised terms.',
  ),
  (
    icon: Icons.gpp_maybe_outlined,
    title: 'Violations and access restrictions',
    body: 'Misuse of EventHub or violation of these terms may be reported to the school. The school may investigate and restrict or disable access as appropriate under its policies. Contact an administrator if you believe an access restriction was made in error.',
  ),
  (
    icon: Icons.mail_outline_rounded,
    title: 'Contact',
    body: 'For questions about these Terms and Conditions, your account, an event, or information shown in EventHub, contact your school administrator or the EventHub support team.',
  ),
];