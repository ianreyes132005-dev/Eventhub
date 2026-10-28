import 'package:flutter/material.dart';

/// The Privacy Policy shown from the login screens (app and web portal).
///
/// Written from what EventHub actually does. When that changes — a new kind
/// of record, a new outside service, who can see what — update this text
/// (and terms_content.dart) in the same change.
const eventHubPrivacy = <({IconData icon, String title, String body})>[
  (
    icon: Icons.info_outline_rounded,
    title: 'Information We Keep',
    body: 'Your school sets up your account, so EventHub starts with the details the school provides:\n\n'
        '• Students: name, LRN, grade level, and strand and section when assigned\n'
        '• Organizers: name, username and organization\n'
        '• Events: your registrations, QR ticket and Ticket ID, check-in status and time, the reason if a check-in is declined, and the reason if you were checked in by hand or your attendance was corrected by the school administrator\n'
        '• Photos: the selfie taken during check-in, and a profile photo if you add one\n'
        '• Activity: sign-in records (name, role, LRN or username, app or web, and time), records of organizer and administrator actions (such as event approvals, check-ins and attendance corrections, with who did them, when, and the student concerned), your AI assistant chats, which notifications you have read, and your app settings\n\n'
        'EventHub does not ask for your email address, phone number or home address. You sign in with your LRN or username.',
  ),
  (
    icon: Icons.settings_suggest_outlined,
    title: 'How It Is Used',
    body: 'Only to run school events:\n\n'
        '• Signing you in and keeping your account secure\n'
        '• Registering you for events and issuing your ticket\n'
        '• Checking you in, including the check-in selfie\n'
        '• Showing announcements and event updates\n'
        '• Attendance records and reports for organizers and the school\n'
        '• Answering the questions you ask the AI assistant',
  ),
  (
    icon: Icons.people_outline_rounded,
    title: 'Who Can See It',
    body: '• You: your own profile, tickets, registrations and check-in status\n'
        '• Event organizers: only the organizer of an event you register for sees that registration, its check-in record and check-in selfie, so they can run check-in\n'
        '• The school administrator: all accounts and records, to manage the system\n\n'
        'Organizers see your name and LRN when you register for their events. Students see the name of the organizer who posted an announcement.',
  ),
  (
    icon: Icons.face_outlined,
    title: 'Photos',
    body: 'Check-in selfies are kept in private storage. Only the event’s organizer and the school administrator can open them, through links that stop working after an hour. They are used only to confirm attendance, and the app asks you before it opens the camera. When the school administrator archives the event, its check-in selfies are deleted; the attendance record stays.\n\n'
        'A profile photo is optional. It is stored so the app can show it, and anyone who has the photo’s link can open it, so only add one you are comfortable sharing.',
  ),
  (
    icon: Icons.cloud_outlined,
    title: 'Services We Use',
    body: 'EventHub runs on Supabase, which stores the database and photos and handles sign-in, over encrypted connections.\n\n'
        'Messages you type into the AI assistant are sent to Groq, an AI service, to write the answer. The assistant is not given your profile or records. Do not type passwords or personal details into it.\n\n'
        'Your information is not sold or used for advertising.',
  ),
  (
    icon: Icons.access_time_outlined,
    title: 'How Long It Is Kept',
    body: 'Records are kept for as long as the school uses them for events and attendance. Sign-in and activity records are kept for at least 90 days; after that, the school administrator can clear them. When the school administrator archives a finished event, its check-in selfies are deleted and its attendance is kept as a read-only record. The administrator can permanently delete archived events, which deletes their registrations and attendance.\n\n'
        'Accounts can be deleted, except accounts with attendance in archived events: those are deactivated instead, so the school’s records stay complete.',
  ),
  (
    icon: Icons.verified_user_outlined,
    title: 'Your Choices',
    body: '• See the details EventHub holds about you in your Profile\n'
        '• Ask the school administrator to correct your details — they can’t be edited in the app\n'
        '• Ask the school administrator to delete your account (it is deactivated instead if your attendance is part of an archived event)\n'
        '• Cancel a registration until check-in opens (1 hour before the event starts), if your ticket hasn’t been scanned\n'
        '• Ask the school administrator to correct your attendance if it’s wrong once check-in has closed\n'
        '• Say Not now when asked for a check-in photo (you may not be checked in without one)\n'
        '• Choose which notifications you get in Profile → Notifications',
  ),
  (
    icon: Icons.mail_outline_rounded,
    title: 'Questions',
    body: 'For questions about your information or this policy, contact your school administrator or email Ianreyes132005@gmail.com.',
  ),
];
