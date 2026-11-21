import 'open_link_stub.dart'
    if (dart.library.html) 'open_link_web.dart'
    as impl;

/// Opens an http(s) address. Other schemes are ignored.
void openExternalLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (uri.scheme != 'https' && uri.scheme != 'http') return;
  if (uri.host.isEmpty) return;
  impl.openExternalLink(uri.toString());
}
