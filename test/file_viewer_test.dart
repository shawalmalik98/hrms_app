import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/files/file_viewer.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/widgets/file_download.dart';

// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Widget _host(Future<({Uint8List bytes, String filename})> Function() fetch) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FileDownload(
            style: FileDownloadStyle.link,
            label: 'certificate',
            fetch: fetch,
          ),
        ),
      ),
    );

void main() {
  test('which files the app shows inside itself', () {
    expect(viewerKindFor('payslip.pdf'), ViewerKind.pdf);
    expect(viewerKindFor('BILL.PDF'), ViewerKind.pdf);
    expect(viewerKindFor('photo.jpg'), ViewerKind.image);
    expect(viewerKindFor('photo.JPEG'), ViewerKind.image);
    expect(viewerKindFor('scan.png'), ViewerKind.image);
    expect(viewerKindFor('notes.txt'), ViewerKind.text);
    // These go to the phone's own app (or are saved).
    expect(viewerKindFor('letter.docx'), ViewerKind.other);
    expect(viewerKindFor('sheet.xlsx'), ViewerKind.other);
    expect(viewerKindFor('noextension'), ViewerKind.other);
  });

  testWidgets('a text file opens inside the app', (tester) async {
    await tester.pumpWidget(
      _host(
        () async => (
          bytes: Uint8List.fromList(utf8.encode('Medical certificate text')),
          filename: 'certificate.txt',
        ),
      ),
    );
    await tester.tap(find.text('certificate'));
    await tester.pumpAndSettle();

    expect(find.text('certificate.txt'), findsOneWidget); // the title
    expect(find.text('Medical certificate text'), findsOneWidget);
    expect(find.byTooltip('Save to phone'), findsOneWidget);
  });

  testWidgets('a picture opens inside the app', (tester) async {
    await tester.pumpWidget(
      _host(() async => (bytes: _png, filename: 'scan.png')),
    );
    await tester.tap(find.text('certificate'));
    await tester.pumpAndSettle();

    expect(find.text('scan.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('the server\'s own message is shown when it has no file', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(() async => throw const ApiException('File Not Found.')),
    );
    await tester.tap(find.text('certificate'));
    await tester.pumpAndSettle();
    expect(find.text('File Not Found.'), findsOneWidget);
  });

  testWidgets('an unexpected failure says what it was', (tester) async {
    await tester.pumpWidget(
      _host(() async => throw StateError('disk is full')),
    );
    await tester.tap(find.text('certificate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open the file'), findsOneWidget);
    expect(find.textContaining('disk is full'), findsOneWidget);
  });
}
