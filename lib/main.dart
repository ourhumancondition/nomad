import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'platform/url_strategy.dart';
import 'ui/nomadic_app.dart';

void main() {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final uri = Uri.base;
  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  runApp(
    NomadicApp(
      initialSection: Section.fromPath(uri.path),
      initialExample: uri.queryParameters['example'] == '1',
      initialSignUp: path == '/signup',
    ),
  );
}
