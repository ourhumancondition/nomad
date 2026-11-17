import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'countries.dart';

/// Looks up the country of the current internet connection.
///
/// The answer is a hint: a VPN, a roaming SIM or a corporate network can
/// put the connection in another country.
abstract class ConnectionCountryLookup {
  /// An ISO alpha-2 code, or null when it is unknown or the lookup failed.
  Future<String?> country();
}

/// Asks this app's own `/api/where` function, which returns only the
/// two-letter country Vercel's edge already derived. No third party is
/// called, and the IP address is not sent back or stored.
class HttpConnectionCountryLookup implements ConnectionCountryLookup {
  HttpConnectionCountryLookup({http.Client? httpClient, this.origin})
    : _http = httpClient ?? http.Client();

  /// Null uses the page origin. Tests pass an absolute origin.
  final String? origin;
  final http.Client _http;

  @override
  Future<String?> country() async {
    if (origin == null && !kIsWeb) return null;
    final base = origin ?? Uri.base.origin;
    try {
      final response = await _http
          .get(
            Uri.parse('$base/api/where'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return parseConnectionCountry(decoded['country']);
    } catch (_) {
      return null;
    }
  }
}

/// Accepts only a known alpha-2 code.
String? parseConnectionCountry(Object? raw) {
  if (raw is! String) return null;
  final code = raw.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return null;
  return countryNames.containsKey(code) ? code : null;
}
