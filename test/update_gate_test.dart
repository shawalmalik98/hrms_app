import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/update/app_updater.dart';
import 'package:hrms_app/features/home/presentation/update_prompt.dart';

void main() {
  // On the test host there is no Android, so the gate finds no update and the
  // app opens normally.
  testWidgets('the app opens when there is nothing to update', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: UpdateGate(child: Text('app'))),
    );
    await tester.pump();
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('the update screen has no way to skip it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const UpdateRequiredDialog(
                info: UpdateInfo(
                  versionCode: 2,
                  versionName: '1.0.1',
                  apkUrl: 'x',
                  notes: 'New things',
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('New things'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsNothing);

    // Tapping outside and the back button do not close it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
  });
}
