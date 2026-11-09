import 'url_strategy_stub.dart'
    if (dart.library.html) 'url_strategy_web.dart'
    as impl;

void configureUrlStrategy() => impl.configureUrlStrategy();
