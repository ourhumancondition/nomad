import 'local_store_memory.dart'
    if (dart.library.html) 'local_store_web.dart'
    as impl;

/// Persistence for the instance origin and the auth payload.
///
/// The auth payload is a PocketBase token. Callers must not log it.
abstract class LocalStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

LocalStore createLocalStore() => impl.createLocalStore();
