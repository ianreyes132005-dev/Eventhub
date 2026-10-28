import 'package:eventhub/features/student/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The header (title, "N new", Mark all as read / All read) fits a narrow
// phone. Signed out, so the list is empty and the header says "All read".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => '/tmp',
    );
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'layout-test-key',
    );
  });

  testWidgets('student Notifications header fits a 360dp phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3; // 360 × 780
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('All read'), findsOneWidget);
    expect(find.text('Mark all as read'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
