import 'local_store.dart';

class MemoryLocalStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;

  @override
  void remove(String key) => values.remove(key);
}

LocalStore createLocalStore() => MemoryLocalStore();
