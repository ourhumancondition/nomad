import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomadic_residence/data/auth_errors.dart';
import 'package:nomadic_residence/data/instance_endpoint.dart';
import 'package:nomadic_residence/data/pocketbase_gateway.dart';
import 'package:nomadic_residence/platform/local_store_memory.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  test('signup validation names the field and hides the generic record error', () {
    final failure = explainAuthFailure(
      ClientException(
        statusCode: 400,
        response: {
          'message': 'Failed to create record.',
          'data': {
            'email': {
              'code': 'validation_not_unique',
              'message': 'Value must be unique.',
            },
          },
        },
      ),
      creatingAccount: true,
    );

    expect(failure.message, contains('already on this database'));
    expect(failure.message.toLowerCase(), isNot(contains('not created')));
    expect(failure.message, isNot(contains('Failed to create record')));
    expect(failure.accountExists, isTrue);
    expect(failure.fields['email'], contains('Sign in'));
    expect(failure.toString(), isNot(contains('password')));
  });

  test('a short password, a mismatch, and a bad email stay on their fields', () {
    final failure = explainAuthFailure(
      ClientException(
        statusCode: 400,
        response: {
          'message': 'Failed to create record.',
          'data': {
            'password': {'code': 'validation_min_text_constraint'},
            'passwordConfirm': {'code': 'validation_values_mismatch'},
            'email': {'code': 'validation_is_email'},
          },
        },
      ),
      creatingAccount: true,
    );

    expect(failure.fields['password'], contains('8 characters'));
    expect(failure.fields['passwordConfirm'], contains('do not match'));
    expect(failure.fields['email'], contains('valid email'));
  });

  test('wrong credentials and closed signup do not mention an administrator', () {
    final wrong = explainAuthFailure(
      ClientException(
        statusCode: 400,
        response: {'message': 'Failed to authenticate.', 'data': {}},
      ),
      creatingAccount: false,
    );
    final closed = explainAuthFailure(
      ClientException(
        statusCode: 403,
        response: {
          'message': 'Only superusers can perform this action.',
          'data': {},
        },
      ),
      creatingAccount: true,
    );

    expect(wrong.message, contains("don't match"));
    expect(wrong.message.toLowerCase(), isNot(contains('superuser')));
    expect(closed.message, contains('not accepting new accounts'));
    expect(closed.message.toLowerCase(), isNot(contains('superuser')));
    expect(closed.message.toLowerCase(), isNot(contains('admin')));
  });

  test('a missing travel collection is recognized and is not a create failure', () {
    expect(
      isMissingTravelTables(
        ClientException(
          statusCode: 404,
          response: {'message': 'Missing collection context.', 'data': {}},
        ),
      ),
      isTrue,
    );
    expect(missingTravelTablesMessage, contains('signed in'));
    expect(missingTravelTablesMessage, contains('travel tables'));
  });

  test('signing out keeps the database address and drops only the session', () {
    final store = MemoryLocalStore();
    final gateway = PocketBaseGateway(store: store);
    final endpoint = InstanceEndpoint.parse(
      'nomad.pockethost.io',
      allowLocal: false,
    );
    gateway.rememberOrigin(endpoint);
    gateway.endpoint = endpoint;
    store.write('nomadic.auth.${endpoint.origin}', 'secret-token');
    gateway.signOut();

    expect(gateway.savedOrigin(), endpoint.origin.toString());
    expect(store.read('nomadic.auth.${endpoint.origin}'), isNull);
    expect(gateway.endpoint, isNull);
  });

  test('wake hour and minute are optional so zero survives PocketBase 0.41', () {
    final source = File(
      'pb_migrations/1794136000_create_travel_collections.js',
    ).readAsStringSync();
    expect(_requiredFlag(source, 'wake_hour'), 'false');
    expect(_requiredFlag(source, 'wake_minute'), 'false');
    expect(_requiredFlag(source, 'personal_day_marker'), 'false');
    expect(source, contains('min: 0'));
    expect(source, contains('max: 23'));
    expect(source, contains('max: 59'));
  });
}

String _requiredFlag(String source, String field) {
  final match = RegExp(
    'name: "$field"[\\s\\S]*?required: (true|false)',
  ).firstMatch(source);
  expect(match, isNotNull, reason: field);
  return match!.group(1)!;
}
