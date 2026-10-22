import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/shared/widgets/stepped_wheel.dart';

// The event forms' hour / minute drums must move one number per step.

const _itemH = 54.0; // the app's drum; the web one is 46
const _start = 600 + 9; // hour drum showing 10 (index % 12 + 1)

Future<FixedExtentScrollController> _pumpWheel(WidgetTester tester) async {
  final ctrl = FixedExtentScrollController(initialItem: _start);
  addTearDown(ctrl.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 120,
          height: _itemH * 5,
          child: SteppedWheel(
            key: const Key('wheel'),
            controller: ctrl,
            itemExtent: _itemH,
            childCount: 12 * 1000,
            itemBuilder: (_, i) => Center(child: Text('${i % 12 + 1}'.padLeft(2, '0'))),
          ),
        ),
      ),
    ),
  ));
  return ctrl;
}

int _hour(FixedExtentScrollController c) => c.selectedItem % 12 + 1;

// Real wheel events carry their own time; [ms] stands in for it here.
Future<void> _wheel(WidgetTester tester, double dy,
    {int ms = 0, PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
  final pointer = TestPointer(1, kind);
  final at = tester.getCenter(find.byKey(const Key('wheel')));
  final time = Duration(milliseconds: ms);
  await tester.sendEventToBinding(pointer.hover(at, timeStamp: time));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy), timeStamp: time));
}

void main() {
  testWidgets('one mouse-wheel notch moves exactly one number (10 → 11)', (tester) async {
    final c = await _pumpWheel(tester);
    expect(_hour(c), 10);
    await _wheel(tester, 100); // Chrome's notch
    await tester.pumpAndSettle();
    expect(_hour(c), 11);
    await _wheel(tester, -100, ms: 500);
    await tester.pumpAndSettle();
    expect(_hour(c), 10);
  });

  testWidgets('notches in a row add up, one each', (tester) async {
    final c = await _pumpWheel(tester);
    for (var i = 0; i < 3; i++) {
      await _wheel(tester, 100, ms: i * 60);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start + 3);
  });

  testWidgets('a high-resolution wheel burst counts as one notch', (tester) async {
    final c = await _pumpWheel(tester);
    for (var i = 0; i < 4; i++) {
      await _wheel(tester, 25, ms: i * 8);
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start + 1);
  });

  testWidgets('a short flick moves exactly one number', (tester) async {
    final c = await _pumpWheel(tester);
    await tester.fling(find.byKey(const Key('wheel')), const Offset(0, -30), 900);
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start + 1);
    await tester.fling(find.byKey(const Key('wheel')), const Offset(0, 30), 900);
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start);
  });

  testWidgets('a quick flick of almost one row does not skip a number', (tester) async {
    final c = await _pumpWheel(tester);
    await tester.fling(find.byKey(const Key('wheel')), const Offset(0, -50), 1200);
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start + 1);
  });

  testWidgets('a slow drag stops on the number it is released on', (tester) async {
    final c = await _pumpWheel(tester);
    await tester.timedDrag(find.byKey(const Key('wheel')), const Offset(0, -_itemH * 2),
        const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(c.selectedItem, _start + 2);
  });

  testWidgets('a long, fast spin still travels further', (tester) async {
    final c = await _pumpWheel(tester);
    await tester.fling(find.byKey(const Key('wheel')), const Offset(0, -200), 3500);
    await tester.pumpAndSettle();
    expect(c.selectedItem, greaterThan(_start + 4));
  });

  testWidgets('tapping a visible number selects it', (tester) async {
    final c = await _pumpWheel(tester);
    await tester.tap(find.text('11'));
    await tester.pumpAndSettle();
    expect(_hour(c), 11);
  });

  testWidgets('trackpad scrolling follows the fingers and settles on a number', (tester) async {
    final c = await _pumpWheel(tester);
    for (var i = 0; i < 3; i++) {
      await _wheel(tester, 20, kind: PointerDeviceKind.trackpad);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(c.offset % _itemH, moreOrLessEquals(0, epsilon: 0.01));
    expect(c.selectedItem, _start + 1); // 60 px ≈ 1.1 rows
  });
}
