import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/gmail_client.dart';
import 'package:nomadic_residence/engine/gmail_access.dart';
import 'package:nomadic_residence/engine/gmail_receipts.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

void main() {
  testWidgets('connect stays disabled in practice data and review does not accept a flight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 8),
      gmail: _FakeGmail(),
    );
    await tester.pumpWidget(
      NomadicApp(
        controller: controller,
        initialExample: true,
        initialSection: Section.gmail,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('gmail.readonly'), findsOneWidget);
    expect(find.textContaining('not proof'), findsOneWidget);
    final connect = tester.widget<FilledButton>(
      find.byKey(const Key('gmail-connect')),
    );
    expect(connect.onPressed, isNull);

    final stays = controller.stays.length;
    await tester.tap(find.byKey(const Key('gmail-fictional')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gmail-review')), findsOneWidget);
    expect(find.textContaining('AC123'), findsWidgets);
    expect(find.textContaining('From: Toronto'), findsNothing);
    final list = find.byType(ListView);
    await tester.dragUntilVisible(
      find.byKey(const Key('gmail-leg-g:amb-msg-001:0')),
      list,
      const Offset(0, -400),
    );
    expect(find.textContaining('none was guessed'), findsWidgets);
    expect(find.textContaining('not a single three-letter code'), findsWidgets);

    await tester.dragUntilVisible(
      find.byKey(const Key('save-g:ac-msg-001:0')),
      list,
      const Offset(0, 400),
    );
    await tester.tap(find.byKey(const Key('save-g:ac-msg-001:0')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('gmail-save')),
      list,
      const Offset(0, -400),
    );
    await tester.drag(list, const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gmail-save')));
    await tester.pumpAndSettle();

    final imported = controller.flights.where(
      (flight) => flight.externalId == 'g:ac-msg-001:0',
    );
    expect(imported, hasLength(1));
    expect(imported.single.reviewState, FlightReviewState.pending);
    expect(imported.single.evidenceStatus, 'booking_only');
    expect(imported.single.gmailFrom, 'tickets@aircanada.example');
    expect(controller.stays, hasLength(stays));
    expect(controller.statusMessage, contains('No country day was added'));
  });

  testWidgets('connect and review screenshots', (tester) async {
    await _loadShotFonts();
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 8),
      gmail: _FakeGmail(),
    );
    controller.kind = SessionKind.connected;
    controller.accountEmail = 'traveler@example.com';
    tester.view.physicalSize = const Size(1280, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('gmail-shot'),
        child: NomadicApp(
          controller: controller,
          initialSection: Section.gmail,
          fontFamily: 'Inter',
          fontFamilyFallback: const ['Noto Color Emoji'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _captureGmailShot(tester, 'gmail-connect');
    await tester.tap(find.byKey(const Key('gmail-fictional')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -640));
    await tester.pumpAndSettle();
    await _captureGmailShot(tester, 'gmail-review');
  });

  test('a revoked link does not call the mailbox', () async {
    final fake = _FakeGmail();
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 8),
      gmail: fake,
    );
    controller.kind = SessionKind.connected;
    controller.gmailConnection = const GmailConnectionStatus(
      state: GmailLinkState.revoked,
    );
    final message = await controller.scanGmail();
    expect(message, contains('revoked'));
    expect(fake.scans, 0);
    final saved = await controller.saveGmailSelection(
      const GmailDraft(saveExternalIds: {'g:ac-msg-001:0'}),
    );
    expect(saved, contains('no Gmail preview'));
    expect(fake.scans, 0);
  });
}

Future<void> _captureGmailShot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(const Key('gmail-shot')))
          as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final dir = Directory('/opt/cursor/artifacts');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  expect(file.lengthSync(), greaterThan(1000));
}

Future<void> _loadShotFonts() async {
  const faces = <String, List<String>>{
    'Inter': [
      '/usr/share/fonts/truetype/macos/Inter-Regular.ttf',
      '/usr/share/fonts/truetype/macos/Inter-Medium.ttf',
      '/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf',
      '/usr/share/fonts/truetype/macos/Inter-Bold.ttf',
    ],
    'Noto Color Emoji': ['/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'],
  };
  for (final entry in faces.entries) {
    if (!File(entry.value.first).existsSync()) continue;
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

class _FakeGmail implements GmailClient {
  int scans = 0;

  @override
  Future<String> authorizeUrl({
    required String authToken,
    required String returnTo,
  }) async {
    return 'https://accounts.google.com/o/oauth2/v2/auth';
  }

  @override
  Future<GmailConnectionStatus> disconnect({required String authToken}) async {
    return const GmailConnectionStatus(state: GmailLinkState.revoked);
  }

  @override
  Future<GmailScanBatch> scan({
    required String authToken,
    String pageToken = '',
  }) async {
    scans += 1;
    return const GmailScanBatch(state: GmailLinkState.revoked, messages: []);
  }

  @override
  Future<GmailConnectionStatus> status({required String authToken}) async {
    return const GmailConnectionStatus(state: GmailLinkState.revoked);
  }
}
