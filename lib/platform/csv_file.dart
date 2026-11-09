import 'csv_file_stub.dart' if (dart.library.html) 'csv_file_web.dart' as impl;

Future<void> downloadTextFile(String filename, String contents) =>
    impl.downloadTextFile(filename, contents);

Future<String?> pickTextFile() => impl.pickTextFile();
