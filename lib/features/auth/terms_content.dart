import 'package:flutter/material.dart';

/// When the Terms and Conditions or the Privacy Policy last changed — shown
/// in both legal dialogs (app and web portal). Update it with the text.
const eventHubLegalUpdated = 'October 28, 2026';

/// The Terms and Conditions shown from the login screens (app and web
/// portal). Keep them true to how EventHub works — see also
/// privacy_content.dart.
const eventHubTerms = <({IconData icon, String title, String body})>[
  (
    icon: Icons.info_outline_rounded,
    title: 'About EventHub',
    body: 'J-Jireh EventHub is the event management system of J-Jireh School, Inc. It provides students with event discovery, registration, QR tickets, attendance updates, and announcements. It also provides authorized organizers with event and registration management tools, and administrators with account and system oversight tools.',
  ),
  (
    icon: Icons.handshake_outlined,
    title: 'Acceptance and Scope',
    body: 'By signing in to or using EventHub, you agree to these Terms and Conditions. These terms apply to the EventHub mobile application, web portal, and the features made available through your account. If you do not agree, do not access or use the system.',
  ),
  (
    icon: Icons.school_outlined,
    title: 'Eligibility and Account Provisioning',
    body: 'EventHub is intended for currently enrolled students and school personnel authorized by J-Jireh School, Inc. Accounts are provisioned by an administrator; users cannot create their own accounts through the app. Your access and available features depend on the role assigned to your account.',
  ),
  (
    icon: Icons.manage_accounts_outlined,
    title: 'Account Security',
    body: 'Keep your sign-in details confidential, use your own account, and sign out when using a shared device. You are responsible for activity performed through your account. Passwords can’t be changed in the app. If you suspect that your credentials have been exposed or your account has been used without permission, contact a school administrator promptly; they can reset your password.',
  ),
  (
    icon: Icons.event_available_outlined,
    title: 'Student Event Use',
    body: 'Students may use EventHub to browse available school events, review event information, register while registration is open (it closes 2 hours after an event starts, or when the event ends if that is sooner), view their registrations, and receive event announcements and updates. You can cancel a registration until check-in opens, 1 hour before the event starts, as long as your ticket hasn’t been scanned; please cancel if you can’t attend. Organizers may change or cancel an event, so check the app for the latest details. Event details and attendance requirements are determined by the school or event organizer. A registration is subject to the event’s published requirements and does not override them.',
  ),
  (
    icon: Icons.qr_code_2_rounded,
    title: 'QR Tickets and Attendance',
    body: 'EventHub issues a QR ticket for each event registration, with a short Ticket ID that an organizer can type if the code won’t scan. Present only your own ticket for check-in. Do not copy, share, alter, or attempt to reuse another person’s QR code or Ticket ID. Organizers scan the code or type the Ticket ID to find a registration and record or continue the event check-in process. The app’s displayed status may change as the organizer processes the check-in.',
  ),
  (
    icon: Icons.schedule_rounded,
    title: 'Check-in Times and Final Attendance',
    body: 'Check-in opens 1 hour before an event starts. Your ticket can be scanned until 30 minutes after the event ends; if it was scanned in time, you can finish checking in (send your selfie and wait for the organizer’s review) until 2 hours after the end. After that, the event’s attendance is final: a ticket that wasn’t checked in is marked Missed, and organizers can no longer change it. Only the school administrator can correct attendance, and the reason for every correction is recorded. If you believe your attendance is wrong, contact the school administrator.',
  ),
  (
    icon: Icons.face_outlined,
    title: 'Selfie Check-In',
    body: 'An organizer may request a selfie as part of an event’s identity verification process; the app asks before it opens the camera. Submit a genuine image of yourself when requested and follow the school’s event instructions. If you don’t send one before check-in closes, you may not be checked in. Selfie images and related registration information are used for the check-in workflow and can be seen by that event’s organizer and the school administrator. Check-in selfies are deleted when the event is archived. Do not upload another person’s image or an unrelated, misleading, or inappropriate image.',
  ),
  (
    icon: Icons.admin_panel_settings_outlined,
    title: 'Organizer and Administrator Tools',
    body: 'Authorized organizers may create events, review registrations, run check-in, send event announcements, and view and export attendance records. A new event must be approved by an administrator before students can see it, and changes to an approved event are sent for approval too. A check-in or a decline is final, and checking a student in without an approved selfie requires a reason, which is recorded. Administrators manage accounts, approve or reject events and changes, may remove announcements (with a reason), archive finished events, may correct attendance after check-in closes (with a recorded reason), and review activity logs, which record actions such as approvals, check-ins and corrections. Use these tools only for your authorized school responsibilities and their intended event-management purposes. Exported files, such as attendance records and student login lists, contain personal information, and login lists also contain initial passwords: share them only with the people they are meant for, and delete them when they are no longer needed.',
  ),
  (
    icon: Icons.campaign_outlined,
    title: 'Announcements and AI Assistant',
    body: 'EventHub may display school or event announcements. Check the event details and follow any instructions provided by the school or organizer. EventHub also includes an AI assistant, in the mobile app and the organizer web portal, for questions about using EventHub. AI responses can be incomplete or inaccurate and are provided as assistance, not as an official school decision. Do not enter passwords or sensitive personal information into the assistant.',
  ),
  (
    icon: Icons.rule_outlined,
    title: 'Acceptable Use',
    body: 'Use EventHub only for legitimate school and event activities. You must not access another person’s account or data, interfere with the service, bypass role permissions or check-in controls, submit false registration information, misuse QR tickets, upload prohibited content, or use the system for unlawful, commercial, or unrelated purposes.',
  ),
  (
    icon: Icons.storage_outlined,
    title: 'Information and System Operation',
    body: 'EventHub processes account, profile, event registration, attendance, announcement, and check-in information to provide its features. The system uses Supabase services for authentication and data storage, and Groq, an AI service, to answer questions typed into the assistant. Access to information is controlled by account roles and the system’s configured permissions. The Privacy Policy explains what is kept and who can see it; questions about school data practices should be directed to a school administrator.',
  ),
  (
    icon: Icons.sync_rounded,
    title: 'Availability and Changes',
    body: 'The school may update, pause, or discontinue a feature for maintenance, operational, or security reasons. EventHub may not always be available or display information without delay. Notifications appear inside the app; EventHub does not send push notifications, text messages, or emails, so check the app for updates. These terms and the system may be updated as the service changes; the date at the top shows when these terms last changed. Continued use after updated terms are made available constitutes acceptance of the revised terms.',
  ),
  (
    icon: Icons.gpp_maybe_outlined,
    title: 'Violations and Access Restrictions',
    body: 'Misuse of EventHub or violation of these terms may be reported to the school. The school may investigate and restrict or disable access as appropriate under its policies. Contact an administrator if you believe an access restriction was made in error.',
  ),
  (
    icon: Icons.mail_outline_rounded,
    title: 'Contact',
    body: 'For questions about these Terms and Conditions, your account, an event, or information shown in EventHub, contact your school administrator or email Ianreyes132005@gmail.com.',
  ),
];
