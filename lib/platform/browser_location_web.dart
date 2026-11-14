import 'package:web/web.dart' as web;

void replaceBrowserLocation(String location) {
  web.window.history.pushState(null, '', location);
}

void assignBrowserLocation(String location) {
  web.window.location.assign(location);
}
