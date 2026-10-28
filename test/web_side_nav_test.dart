import 'package:eventhub/shared/widgets/web/web_account_menu.dart';
import 'package:eventhub/shared/widgets/web/web_side_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The web portals' sidebar and account menu: titled groups, always open on
// wide windows, a drawer on narrow ones, and keyboard use.
enum _Page { dashboard, events, registrations, profile }

const _palette = WebNavPalette(
  background: LinearGradient(colors: [Colors.white, Colors.white]),
  border: Color(0xFFCBD5E1),
  text: Color(0xFF3A3324),
  activeText: Color(0xFF111827),
  icon: Color(0xFF6B5E47),
  label: Color(0xFF7A6A52),
  hover: Color(0xFFF1F5F9),
  accent: Color(0xFFD4AA60),
  accentStrong: Color(0xFFA16207),
  focus: Color(0xFF2563EB),
);

const _groups = [
  WebNavGroup(entries: [
    WebNavEntry(page: _Page.dashboard, icon: Icons.dashboard_rounded, label: 'Dashboard'),
  ]),
  WebNavGroup(title: 'Manage', entries: [
    WebNavEntry(page: _Page.events, icon: Icons.event_rounded, label: 'Events'),
    WebNavEntry(
      page: _Page.registrations,
      icon: Icons.how_to_reg_rounded,
      label: 'Registrations',
      badge: 3,
      badgeTip: '3 selfies waiting for your review',
    ),
  ]),
  WebNavGroup(title: 'Account', entries: [
    WebNavEntry(page: _Page.profile, icon: Icons.person_rounded, label: 'Profile'),
  ]),
];

void main() {
  test('narrow windows get a drawer; from 1024 px the sidebar stays open', () {
    expect(webNavUsesDrawer(900), isTrue);
    expect(webNavUsesDrawer(1023), isTrue);
    expect(webNavUsesDrawer(1024), isFalse);
    expect(webNavUsesDrawer(1440), isFalse);
  });

  Future<List<_Page>> pumpNav(WidgetTester tester, {VoidCallback? onClose}) async {
    final picked = <_Page>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 260,
            height: 700,
            child: WebSideNav<_Page>(
              portalLabel: 'Organizer portal',
              palette: _palette,
              groups: _groups,
              current: _Page.events,
              onSelect: picked.add,
              onClose: onClose,
            ),
          ),
        ),
      ),
    ));
    return picked;
  }

  testWidgets('groups under their titles; a click opens the page', (tester) async {
    final picked = await pumpNav(tester);
    expect(find.text('ORGANIZER PORTAL'), findsOneWidget);
    expect(find.text('MANAGE'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // the Registrations badge
    expect(find.text('Collapse'), findsNothing); // removed: always open

    await tester.tap(find.text('Profile'));
    expect(picked, [_Page.profile]);

    // Screen readers hear one button per link, can activate it, and know
    // which page is open; the badge's meaning is part of its name.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Events')),
      isSemantics(isButton: true, isSelected: true, isFocusable: true,
          hasTapAction: true),
    );
    expect(
      find.bySemanticsLabel('Registrations, 3 selfies waiting for your review'),
      findsOneWidget,
    );
  });

  testWidgets('the keyboard reaches every link: Tab, then Enter', (tester) async {
    final picked = await pumpNav(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Dashboard
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Events
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Registrations
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(picked, [_Page.dashboard, _Page.registrations]);
  });

  testWidgets('the drawer closes with its button or Esc', (tester) async {
    var closed = 0;
    await pumpNav(tester, onClose: () => closed++);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.byTooltip('Close menu'));
    expect(closed, 2);
  });

  testWidgets('account menu: name, role, a dark mode switch and sign out', (tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: WebAccountMenu(
            name: 'Maria Santos',
            role: 'Organizer',
            avatar: const CircleAvatar(radius: 17),
            accent: const Color(0xFFD4AA60),
            actions: [
              WebAccountAction(icon: Icons.dark_mode_outlined, label: 'Dark mode', toggled: false,
                  onSelected: () => chosen.add('dark')),
              WebAccountAction(icon: Icons.logout_rounded, label: 'Sign out', danger: true,
                  onSelected: () => chosen.add('signout')),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('Maria Santos'), findsOneWidget); // the button
    expect(
      tester.getSemantics(find.bySemanticsLabel('Account menu, Maria Santos')),
      isSemantics(isButton: true, hasTapAction: true, isFocusable: true,
          hasExpandedState: true, isExpanded: false),
    );
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    expect(find.text('Organizer'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    // It opens under the button, right edges lined up (6 = the menu's padding).
    final button = tester.getRect(find.bySemanticsLabel('Account menu, Maria Santos'));
    final signOutRow = tester.getRect(find.widgetWithText(MenuItemButton, 'Sign out'));
    expect(signOutRow.right, moreOrLessEquals(button.right - 6));
    expect(signOutRow.top, greaterThan(button.bottom));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Account menu, Maria Santos')),
      isSemantics(isExpanded: true),
    );
    // Dark mode is one control that says whether it's on (a button on the
    // web; Flutter marks menu rows as buttons only there).
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dark mode')),
      isSemantics(hasTapAction: true, hasToggledState: true, isToggled: false),
    );

    // Dark mode keeps the menu open; Sign out closes it.
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsNothing);
    expect(chosen, ['dark', 'signout']);
  });
}
