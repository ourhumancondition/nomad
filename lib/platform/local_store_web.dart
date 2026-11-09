import 'package:web/web.dart' as web;

import 'local_store.dart';

class WebLocalStore implements LocalStore {
  @override
  String? read(String key) => web.window.localStorage.getItem(key);

  @override
  void write(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  @override
  void remove(String key) {
    web.window.localStorage.removeItem(key);
  }
}

LocalStore createLocalStore() => WebLocalStore();
