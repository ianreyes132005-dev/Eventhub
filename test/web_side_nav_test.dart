import 'package:eventhub/shared/widgets/web/web_account_menu.dart';
import 'package:eventhub/shared/widgets/web/web_side_nav.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The web portals' sidebar and account menu: titled groups, an icon rail,
// a drawer on narrow windows, remembered collapse and keyboard use.
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
  test('the sidebar follows the window width', () {
    expect(webNavLayoutFor(900), WebNavLayout.drawer);
    expect(webNavLayoutFor(1023), WebNavLayout.drawer);
    expect(webNavLayoutFor(1024), WebNavLayout.medium);
    expect(webNavLayoutFor(1279), WebNavLayout.medium);
    expect(webNavLayoutFor(1280), WebNavLayout.wide);
  });

  test('collapse is remembered per portal: open on wide, a rail on medium at first', () async {
    SharedPreferences.setMockInitialValues({});
    var v = await WebNavPrefs.load('organizer');
    expect((v.wide, v.medium), (false, true));

    await WebNavPrefs.save('organizer', WebNavLayout.wide, true);
    await WebNavPrefs.save('organizer', WebNavLayout.medium, false);
    await WebNavPrefs.save('organizer', WebNavLayout.drawer, true); // ignored
    v = await WebNavPrefs.load('organizer');
    expect((v.wide, v.medium), (true, false));
    // The admin portal keeps its own.
    v = await WebNavPrefs.load('admin');
    expect((v.wide, v.medium), (false, true));
  });

  Future<List<_Page>> pumpNav(
    WidgetTester tester, {
    bool collapsed = false,
    VoidCallback? onToggle,
    VoidCallback? onClose,
  }) async {
    final picked = <_Page>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: collapsed ? 76 : 260,
            height: 700,
            child: WebSideNav<_Page>(
              portalLabel: 'Organizer portal',
              palette: _palette,
              groups: _groups,
              current: _Page.events,
              collapsed: collapsed,
              onSelect: picked.add,
              onToggleCollapse: onToggle,
              onClose: onClose,
            ),
          ),
        ),
      ),
    ));
    return picked;
  }

  testWidgets('groups under their titles; a click opens the page', (tester) async {
    var toggled = 0;
    final picked = await pumpNav(tester, onToggle: () => toggled++);
    expect(find.text('ORGANIZER PORTAL'), findsOneWidget);
    expect(find.text('MANAGE'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // the Registrations badge

    await tester.tap(find.text('Profile'));
    await tester.tap(find.text('Collapse'));
    expect(picked, [_Page.profile]);
    expect(toggled, 1);

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

  testWidgets('collapsed: an icon rail without labels or titles', (tester) async {
    await pumpNav(tester, collapsed: true, onToggle: () {});
    expect(find.text('Events'), findsNothing);
    expect(find.text('MANAGE'), findsNothing);
    expect(find.byIcon(Icons.event_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_double_arrow_right_rounded), findsOneWidget);

    // Hover: the name shows beside the icon, not over the next one.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final icon = tester.getRect(find.byIcon(Icons.event_rounded));
    await mouse.moveTo(icon.center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final tip = tester.getRect(find.text('Events'));
    expect(tip.left, greaterThan(icon.right));
    expect(tip.center.dy, moreOrLessEquals(icon.center.dy, epsilon: 1));
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
