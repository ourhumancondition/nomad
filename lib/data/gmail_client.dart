import 'dart:convert';

import 'package:http/http.dart' as http;

import '../engine/gmail_access.dart';
import '../engine/gmail_receipts.dart';

class GmailConnectionStatus {
  const GmailConnectionStatus({
    required this.state,
    this.googleEmail = '',
    this.scope = '',
    this.connectedAt = '',
  });

  const GmailConnectionStatus.missing() : this(state: GmailLinkState.missing);

  final GmailLinkState state;
  final String googleEmail;
  final String scope;
  final String connectedAt;
}

class GmailScanBatch {
  const GmailScanBatch({
    required this.state,
    required this.messages,
    this.nextPageToken = '',
    this.skipped = 0,
  });

  final GmailLinkState state;
  final List<ReceiptMessage> messages;
  final String nextPageToken;
  final int skipped;
}

class GmailClientException implements Exception {
  const GmailClientException(this.message, {this.code = ''});

  final String message;
  final String code;
}

/// Talks to the same-origin Gmail broker. Tokens are not returned.
abstract class GmailClient {
  Future<GmailConnectionStatus> status({required String authToken});

  Future<String> authorizeUrl({
    required String authToken,
    required String returnTo,
  });

  Future<GmailScanBatch> scan({
    required String authToken,
    String pageToken = '',
  });

  Future<GmailConnectionStatus> disconnect({required String authToken});
}

class HttpGmailClient implements GmailClient {
  HttpGmailClient({http.Client? httpClient, this.origin})
    : _http = httpClient ?? http.Client();

  /// Null uses the page origin. Tests pass an absolute origin.
  final String? origin;
  final http.Client _http;

  @override
  Future<GmailConnectionStatus> status({required String authToken}) async {
    final payload = await _send('GET', '/api/gmail/status', authToken);
    return _status(payload);
  }

  @override
  Future<String> authorizeUrl({
    required String authToken,
    required String returnTo,
  }) async {
    final payload = await _send(
      'POST',
      '/api/gmail/start',
      authToken,
      body: {'returnTo': returnTo},
    );
    final url = payload['authorizeUrl'];
    if (url is! String || !url.startsWith('https://accounts.google.com/')) {
      throw const GmailClientException(
        'Gmail did not return a Google sign-in address.',
      );
    }
    return url;
  }

  @override
  Future<GmailScanBatch> scan({
    required String authToken,
    String pageToken = '',
  }) async {
    final payload = await _send(
      'POST',
      '/api/gmail/scan',
      authToken,
      body: {'pageToken': pageToken},
    );
    final state = gmailLinkState(_string(payload, 'state'));
    if (!scanAllowed(state)) {
      return GmailScanBatch(state: state, messages: const []);
    }
    final messages = <ReceiptMessage>[];
    final raw = payload['messages'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final id = _string(item, 'messageId');
        final from = _string(item, 'from');
        final date = _string(item, 'date');
        final text = _string(item, 'text');
        if (id.isEmpty) continue;
        messages.add(
          ReceiptMessage(
            messageId: id,
            fromAddress: from,
            receivedAt: date,
            text: text,
            truncated: item['truncated'] == true,
          ),
        );
      }
    }
    return GmailScanBatch(
      state: state,
      messages: messages,
      nextPageToken: _string(payload, 'nextPageToken'),
      skipped: payload['skipped'] is int ? payload['skipped'] as int : 0,
    );
  }

  @override
  Future<GmailConnectionStatus> disconnect({required String authToken}) async {
    final payload = await _send('POST', '/api/gmail/disconnect', authToken);
    return _status(payload);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    String authToken, {
    Map<String, Object?>? body,
  }) async {
    final base = origin ?? Uri.base.origin;
    final uri = Uri.parse('$base$path');
    final headers = <String, String>{
      'Authorization': 'Bearer $authToken',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await _http.get(uri, headers: headers);
      } else {
        response = await _http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        );
      }
    } catch (_) {
      throw const GmailClientException('The Gmail broker could not be reached.');
    }
    Map<String, Object?> payload = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          payload = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } on FormatException {
        payload = const {};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GmailClientException(
        _safeMessage(payload, response.statusCode),
        code: _string(payload, 'error'),
      );
    }
    return payload;
  }
}

GmailConnectionStatus _status(Map<String, Object?> payload) {
  return GmailConnectionStatus(
    state: gmailLinkState(_string(payload, 'state')),
    googleEmail: _string(payload, 'googleEmail'),
    scope: _string(payload, 'scope'),
    connectedAt: _string(payload, 'connectedAt'),
  );
}

String _string(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  return '';
}

String _safeMessage(Map<String, Object?> payload, int status) {
  final code = _string(payload, 'error');
  return switch (code) {
    'not_configured' =>
      'Gmail is not set up on this deployment yet. Nothing was read.',
    'revoked' => 'Gmail access is revoked. No mailbox was read.',
    'unauthorized' => 'Sign in again before using Gmail.',
    'scope' => 'Google offered more than read-only Gmail. Nothing was stored.',
    'origin' => 'This page is not an allowed return address.',
    _ => 'The Gmail broker refused the request ($status).',
  };
}
