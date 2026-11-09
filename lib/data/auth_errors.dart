import 'package:pocketbase/pocketbase.dart';

class GatewayException implements Exception {
  GatewayException(
    this.message, {
    this.statusCode,
    this.fields = const {},
    this.accountExists = false,
  });

  final String message;
  final int? statusCode;
  final Map<String, String> fields;

  /// True when this email already has an account, including a create that
  /// succeeded and a later step that failed.
  final bool accountExists;

  @override
  String toString() => message;
}

/// Turns a PocketBase auth response into a short message and field hints.
///
/// Server text is not copied through. PocketBase's own messages can be
/// generic ("Failed to create record.") and this keeps passwords out of the UI.
GatewayException explainAuthFailure(
  ClientException error, {
  required bool creatingAccount,
}) {
  final original = error.originalError?.toString().toLowerCase() ?? '';
  if (original.contains('redirect')) {
    return GatewayException(
      'The database URL redirected. The request was refused.',
      statusCode: error.statusCode,
    );
  }
  if (error.isAbort || error.statusCode == 0) {
    return GatewayException(
      'The database could not be reached. Check the address and try again.',
      statusCode: error.statusCode,
    );
  }

  final fields = _fieldHints(error.response['data']);
  final message = (error.response['message'] ?? '').toString().toLowerCase();
  final status = error.statusCode;

  if (_emailAlreadyExists(error.response['data'])) {
    return GatewayException(
      'An account with this email is already on this database. Sign in with it.',
      statusCode: status,
      fields: const {
        'email':
            'This email already has an account. Sign in instead of creating another one.',
      },
      accountExists: true,
    );
  }
  if (creatingAccount &&
      (status == 403 || message.contains('only superusers'))) {
    return GatewayException(
      'This database is not accepting new accounts. Sign in if you already have one.',
      statusCode: status,
      accountExists: false,
    );
  }
  if (!creatingAccount &&
      (message.contains('failed to authenticate') || status == 400 && fields.isEmpty)) {
    return GatewayException(
      "That email and password don't match an account on this database.",
      statusCode: status,
    );
  }
  if (fields.isNotEmpty) {
    return GatewayException(
      creatingAccount
          ? 'The account was not created. Fix the fields below.'
          : 'Sign-in was not accepted. Fix the fields below.',
      statusCode: status,
      fields: fields,
    );
  }
  if (creatingAccount) {
    return GatewayException(
      'The account was not created. Use a valid email and a password of at least 8 characters.',
      statusCode: status,
    );
  }
  return GatewayException(
    'The database did not accept the sign-in.',
    statusCode: status,
  );
}

/// Shown after the account session exists but the travel tables are absent.
const missingTravelTablesMessage =
    'You are signed in. This database does not have the travel tables yet, so there is nothing to count.';

bool isMissingTravelTables(ClientException error) {
  final message = (error.response['message'] ?? '').toString().toLowerCase();
  return error.statusCode == 404 && message.contains('missing collection');
}

Map<String, String> _fieldHints(Object? data) {
  if (data is! Map) return const {};
  final hints = <String, String>{};
  for (final entry in data.entries) {
    final name = entry.key.toString();
    if (name != 'email' && name != 'password' && name != 'passwordConfirm') {
      continue;
    }
    final code = _code(entry.value);
    final hint = _hint(name, code);
    if (hint != null) hints[name] = hint;
  }
  return hints;
}

bool _emailAlreadyExists(Object? data) {
  if (data is! Map) return false;
  return _code(data['email']) == 'validation_not_unique';
}

String? _code(Object? value) {
  if (value is Map && value['code'] is String) return value['code'] as String;
  return null;
}

String? _hint(String field, String? code) {
  switch (field) {
    case 'email':
      switch (code) {
        case 'validation_not_unique':
          return 'An account with this email is already on this database. Sign in instead.';
        case 'validation_is_email':
          return 'Enter a valid email address.';
        case 'validation_required':
          return 'Enter an email address.';
        default:
          return 'Check the email address.';
      }
    case 'password':
      switch (code) {
        case 'validation_min_text_constraint':
          return 'Use a password of at least 8 characters.';
        case 'validation_required':
          return 'Enter a password.';
        default:
          return 'Check the password. It needs at least 8 characters.';
      }
    case 'passwordConfirm':
      switch (code) {
        case 'validation_values_mismatch':
          return 'Those passwords do not match.';
        case 'validation_required':
          return 'Enter the password again.';
        default:
          return 'Enter the same password again.';
      }
    default:
      return null;
  }
}
