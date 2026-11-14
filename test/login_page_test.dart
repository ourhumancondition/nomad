import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/instance_endpoint.dart';
import 'package:nomadic_residence/data/pocketbase_gateway.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/platform/local_store_memory.dart';
import 'package:nomadic_residence/state/app_controller.dart';
import 'package:nomadic_residence/ui/nomadic_app.dart';

void main() {
  test('a fresh visit remembers the default server and no password', () async {
    final store = MemoryLocalStore();
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 14),
      gateway: PocketBaseGateway(store: store),
    );
    await controller.restoreIfSaved();

    expect(controller.isConnected, isFalse);
    expect(controller.restoring, isFalse);
    expect(controller.pendingEndpoint?.origin.toString(), defaultInstanceUrl);
    expect(store.read(instanceOriginKey), defaultInstanceUrl);
    expect(
      store.values.values.any((value) => value.contains('secret')),
      isFalse,
    );
  });

  test('sign out drops the session and keeps the email and server', () {
    final store = MemoryLocalStore();
    final gateway = PocketBaseGateway(store: store);
    final endpoint = InstanceEndpoint.parse(
      defaultInstanceUrl,
      allowLocal: false,
    );
    gateway.rememberOrigin(endpoint);
    gateway.rememberEmail('ada@example.test');
    gateway.endpoint = endpoint;
    store.write('nomadic.auth.${endpoint.origin}', '{"token":"secret-token"}');
    const password = 'not-stored-plain-password';
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 14),
      gateway: gateway,
    );
    controller.kind = SessionKind.connected;
    controller.accountEmail = 'ada@example.test';
    controller.instanceOrigin = endpoint.origin.toString();
    controller.pendingEndpoint = endpoint;

    controller.signOut();

    expect(controller.isConnected, isFalse);
    expect(gateway.savedEmail(), 'ada@example.test');
    expect(gateway.savedOrigin(), defaultInstanceUrl);
    expect(store.read('nomadic.auth.${endpoint.origin}'), isNull);
    expect(
      store.values.values.any((value) => value.contains(password)),
      isFalse,
    );
  });

  testWidgets('the remembered email is filled in after sign out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryLocalStore();
    final gateway = PocketBaseGateway(store: store);
    gateway.rememberEmail('ada@example.test');
    final controller = AppController(
      clock: () => LocalDate(2026, 11, 14),
      gateway: gateway,
    );
    controller.kind = SessionKind.connected;
    controller.accountEmail = 'ada@example.test';
    await tester.pumpWidget(NomadicApp(controller: controller));
    expect(find.byKey(const Key('days-title')), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gate-title')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auth-email')))
          .controller
          ?.text,
      'ada@example.test',
    );
    final password = tester.widget<TextField>(
      find.byKey(const Key('auth-password')),
    );
    expect(password.obscureText, isTrue);
    expect(password.autofillHints, contains(AutofillHints.password));
    expect(password.controller?.text, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auth-email')))
          .autofillHints,
      contains(AutofillHints.email),
    );
  });

  testWidgets('login and sign-up screenshots', (tester) async {
    await _loadInter();
    final controller = AppController(clock: () => LocalDate(2026, 11, 14));
    controller.gateway.rememberEmail('ada@example.test');
    await _frame(
      tester,
      NomadicApp(controller: controller, fontFamily: 'Inter'),
      const Size(1280, 900),
    );
    await _capture(tester, 'login-desktop');
    await tester.tap(find.byKey(const Key('go-to-signup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-title')), findsOneWidget);
    await _capture(tester, 'signup-desktop');
    tester.view.physicalSize = const Size(390, 1000);
    await tester.pumpAndSettle();
    await _capture(tester, 'signup-phone');
  });
}

Future<void> _frame(WidgetTester tester, Widget app, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(key: const Key('auth-shot'), child: app),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject(
    find.byKey(const Key('auth-shot')),
  ) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  final dir = Directory('/opt/cursor/artifacts');
  dir.createSync(recursive: true);
  final file = File('${dir.path}/$name.png');
  file.writeAsBytesSync(bytes.buffer.asUint8List());
  expect(file.lengthSync(), greaterThan(1000));
}

Future<void> _loadInter() async {
  const paths = [
    '/usr/share/fonts/truetype/macos/Inter-Regular.ttf',
    '/usr/share/fonts/truetype/macos/Inter-Medium.ttf',
    '/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf',
    '/usr/share/fonts/truetype/macos/Inter-Bold.ttf',
  ];
  if (!File(paths.first).existsSync()) return;
  final loader = FontLoader('Inter');
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
