/// An allowlisted PocketBase origin.
///
/// The app talks to that origin directly from the browser. There is no proxy,
/// so a rejected URL is never requested. PocketHost travel data belongs on
/// `https://<instance>.pockethost.io`. Loopback is only for disposable tests.
class InstanceEndpoint {
  InstanceEndpoint._(this.origin, {required this.loopback});

  final Uri origin;
  final bool loopback;

  Uri get healthUri => Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/api/health',
  );

  String get displayHost => origin.host;

  static final _label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');

  static InstanceEndpoint? tryParse(String raw, {required bool allowLocal}) {
    try {
      return parse(raw, allowLocal: allowLocal);
    } on FormatException {
      return null;
    }
  }

  static InstanceEndpoint parse(String raw, {required bool allowLocal}) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter the database URL.');
    }
    // A bare PocketHost name is the same origin as its https URL.
    // An explicit http URL is left unchanged and rejected below.
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    if (trimmed.contains('@') ||
        trimmed.contains('\\') ||
        trimmed.contains(' ') ||
        trimmed.contains('#') ||
        trimmed.contains('?')) {
      throw const FormatException(
        'The URL must be a plain https origin, without a user, query, or fragment.',
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException(
        'Enter a full URL such as https://your-instance.pockethost.io.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'The URL cannot contain a username or password.',
      );
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException(
        'Use only the instance origin. Leave off /api and other paths.',
      );
    }
    if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw const FormatException(
        'The URL cannot contain a query or fragment.',
      );
    }

    final host = uri.host.toLowerCase();
    final loopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (loopback) {
      if (!allowLocal) {
        throw const FormatException(
          'Local databases are available in debug builds and disposable tests.',
        );
      }
      if (uri.scheme != 'http') {
        throw const FormatException('Loopback databases use http.');
      }
      if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
        throw const FormatException('That port is not valid.');
      }
      return InstanceEndpoint._(
        Uri(scheme: 'http', host: host, port: uri.hasPort ? uri.port : null),
        loopback: true,
      );
    }

    if (uri.scheme != 'https') {
      throw const FormatException('PocketHost instances use https.');
    }
    if (uri.hasPort && uri.port != 443) {
      throw const FormatException(
        'PocketHost instances use the default https port.',
      );
    }
    if (!host.endsWith('.pockethost.io')) {
      throw const FormatException(
        'Travel databases on PocketHost use a single subdomain of pockethost.io.',
      );
    }
    final label = host.substring(0, host.length - '.pockethost.io'.length);
    if (label.isEmpty || label.contains('.') || !_label.hasMatch(label)) {
      throw const FormatException(
        'Use one instance name, such as https://your-instance.pockethost.io.',
      );
    }
    return InstanceEndpoint._(
      Uri(scheme: 'https', host: host),
      loopback: false,
    );
  }
}
