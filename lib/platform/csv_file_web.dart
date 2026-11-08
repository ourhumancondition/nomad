import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> downloadTextFile(String filename, String contents) async {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}

Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv';
  input.addEventListener(
    'change',
    (web.Event event) {
      final file = input.files?.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final reader = web.FileReader();
      reader.addEventListener(
        'loadend',
        (web.Event event) {
          final result = reader.result;
          if (!completer.isCompleted) {
            completer.complete(
              result == null ? '' : (result as JSString).toDart,
            );
          }
        }.toJS,
      );
      reader.readAsText(file);
    }.toJS,
  );
  input.click();
  return completer.future;
}
