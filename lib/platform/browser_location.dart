import 'browser_location_stub.dart'
    if (dart.library.html) 'browser_location_web.dart'
    as impl;

void replaceBrowserLocation(String location) =>
    impl.replaceBrowserLocation(location);
