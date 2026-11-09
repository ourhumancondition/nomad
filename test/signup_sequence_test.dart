import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/pocketbase_gateway.dart';
import 'package:nomadic_residence/engine/local_date.dart';
import 'package:nomadic_residence/engine/models.dart';
import 'package:nomadic_residence/platform/local_store_memory.dart';
import 'package:nomadic_residence/state/app_controller.dart';

void main() {
  final binary = File(
    Platform.environment['PB_BIN'] ?? '/tmp/pb041/pocketbase',
  );
  final live = binary.existsSync();

  test(
    'a created account stays signed in when travel tables are missing',
    () async {
      final home = await Directory.systemTemp.createTemp('nomad-signup-');
      final port = 18171;
      final origin = 'http://127.0.0.1:$port';
      final process = await Process.start(binary.path, [
        'serve',
        '--dir',
        '${home.path}/pb_data',
        '--http',
        '127.0.0.1:$port',
      ], workingDirectory: home.path);
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        await home.delete(recursive: true);
      });
      await _waitHealthy(origin);

      final controller = AppController(
        clock: () => LocalDate(2026, 11, 8),
        gateway: PocketBaseGateway(store: MemoryLocalStore()),
        allowLocalEndpoints: true,
      );
      const email = 'person@example.test';
      const password = 'local-disposable-user-password';

      expect(await controller.checkHealth(origin), isNull);
      expect(await controller.signUp(email, password, password), isNull);
      expect(controller.isConnected, isTrue);
      expect(controller.errorMessage, isNull);
      expect(controller.accountEmail, email);
      expect(controller.notices.single, contains('signed in'));
      expect(controller.notices.single, contains('travel tables'));
      expect(
        controller.notices.join().toLowerCase(),
        isNot(contains('not created')),
      );
      expect(controller.notices.join(), isNot(contains('Failed to create')));
      expect(await _userCount(origin, '${home.path}/pb_data'), 1);

      controller.signOut();
      expect(controller.isConnected, isFalse);
      expect(controller.pendingEndpoint, isNotNull);
      final duplicate = await controller.signUp(email, password, password);
      expect(duplicate, contains('already on this database'));
      expect(duplicate!.toLowerCase(), isNot(contains('not created')));
      expect(duplicate, isNot(contains('Failed to create record')));
      expect(controller.preferSignIn, isTrue);
      expect(controller.isConnected, isFalse);
      expect(await _userCount(origin, '${home.path}/pb_data'), 1);

      final wrong = await controller.signIn(email, 'wrong-password-value');
      expect(wrong, contains("don't match"));
      expect(wrong, isNot(contains('Failed to create record')));
      expect(await controller.signIn(email, password), isNull);
      expect(controller.isConnected, isTrue);
      expect(controller.notices.single, contains('travel tables'));

      controller.signOut();
      process.kill();
      await process.exitCode;
      await Directory('${home.path}/pb_migrations').create();
      await File(
        'pb_migrations/1794136000_create_travel_collections.js',
      ).copy('${home.path}/pb_migrations/1794136000_create_travel_collections.js');
      final restarted = await Process.start(binary.path, [
        'serve',
        '--dir',
        '${home.path}/pb_data',
        '--migrationsDir',
        '${home.path}/pb_migrations',
        '--http',
        '127.0.0.1:$port',
      ], workingDirectory: home.path);
      addTearDown(() async {
        restarted.kill();
        await restarted.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            restarted.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      });
      await _waitHealthy(origin);

      expect(await controller.signIn(email, password), isNull);
      expect(controller.isConnected, isTrue);
      expect(controller.notices, isEmpty);
      expect(
        await controller.saveRules(
          nextRules: const CountingRules(wakeHour: 0, wakeMinute: 0),
          nextStatuses: defaultEvidenceStatuses,
        ),
        isNull,
      );
      expect(controller.rules.wakeHour, 0);
      expect(controller.rules.wakeMinute, 0);
      expect(await _userCount(origin, '${home.path}/pb_data'), 1);
    },
    skip: live ? false : 'PocketBase 0.41.1 binary is not on this machine',
  );
}

Future<void> _waitHealthy(String origin) async {
  final client = HttpClient();
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      final request = await client.getUrl(Uri.parse('$origin/api/health'));
      final response = await request.close();
      if (response.statusCode == 200) {
        await response.drain<void>();
        client.close(force: true);
        return;
      }
      await response.drain<void>();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  client.close(force: true);
  throw StateError('disposable database did not become healthy');
}

Future<int> _userCount(String origin, String dataDir) async {
  final client = HttpClient();
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    final request = await client.openUrl(method, Uri.parse('$origin$path'));
    request.headers.contentType = ContentType.json;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, token);
    }
    if (body != null) request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic> || response.statusCode >= 300) {
      throw StateError('disposable admin call failed');
    }
    return parsed;
  }

  final binary = Platform.environment['PB_BIN'] ?? '/tmp/pb041/pocketbase';
  final upsert = await Process.run(binary, [
    'superuser',
    'upsert',
    'local-super@example.test',
    'local-disposable-super-password',
    '--dir',
    dataDir,
  ]);
  if (upsert.exitCode != 0) {
    throw StateError('disposable superuser was not saved');
  }
  final auth = await send(
    'POST',
    '/api/collections/_superusers/auth-with-password',
    body: {
      'identity': 'local-super@example.test',
      'password': 'local-disposable-super-password',
    },
  );
  final listed = await send(
    'GET',
    '/api/collections/users/records?perPage=1&fields=id',
    token: auth['token'] as String,
  );
  client.close(force: true);
  return listed['totalItems'] as int;
}
