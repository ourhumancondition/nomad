import 'package:web/web.dart' as web;

void openExternalLink(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
