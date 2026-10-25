import 'package:eventhub/features/organizer/mobile/registrations/organizer_registrations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  testWidgets('organizer Registrations loading state lays out in dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: IndexedStack(
              index: 0,
              children: [
                const SizedBox.expand(),
                const RegistrationsScreen(showAsEmbedded: true),
                const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
